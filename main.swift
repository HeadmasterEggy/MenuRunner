import AppKit
import ServiceManagement
import IOKit.ps
import IOKit

// MARK: - 语言（跟随系统 / 中文 / English）
enum Lang {
    static var mode: String {
        get { UserDefaults.standard.string(forKey: "lang") ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: "lang") }
    }
    static var isZh: Bool {
        switch mode {
        case "zh": return true
        case "en": return false
        default:   return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }
}
func L(_ zh: String, _ en: String) -> String { Lang.isZh ? zh : en }

// MARK: - 系统信息：CPU / 内存 / 存储 / 电池
struct CPULoad { var user = 0.0, system = 0.0, idle = 1.0; var total: Double { user + system } }

final class CPUMonitor {
    private var prev: host_cpu_load_info?

    /// 两次调用之间的 CPU 占比（0.0 ~ 1.0）
    func load() -> CPULoad {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return CPULoad() }
        defer { prev = info }
        guard let p = prev else { return CPULoad() }
        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let sys  = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + sys + idle + nice
        guard total > 0 else { return CPULoad() }
        return CPULoad(user: (user + nice) / total, system: sys / total, idle: idle / total)
    }
}

enum SystemInfo {
    /// 已用内存（与“活动监视器”的“已使用内存”口径接近：App 内存 + 联动 + 压缩）
    struct Memory { var used = 0.0, total = 1.0, app = 0.0, wired = 0.0, compressed = 0.0 }

    /// 已用内存（与“活动监视器”口径接近：App 内存 + 联动内存 + 被压缩）
    static func memory() -> Memory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard r == KERN_SUCCESS else { return Memory(total: total) }
        let page = Double(vm_kernel_page_size)
        let app = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page
        let wired = Double(stats.wire_count) * page
        let comp = Double(stats.compressor_page_count) * page
        return Memory(used: app + wired + comp, total: total, app: app, wired: wired, compressed: comp)
    }

    static func storage() -> (used: Double, total: Double)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Double(total) - Double(free), Double(total))
    }

    /// 电池百分比和状态；台式机没有电池时返回 nil
    static func battery() -> (percent: Int, state: String)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let state = charging ? "charging" : (onAC ? "ac" : "battery")
            return (Int((Double(cur) / Double(max) * 100).rounded()), state)
        }
        return nil
    }

    static func stateText(_ s: String) -> String {
        switch s {
        case "charging": return L("充电中", "Charging")
        case "ac":       return L("已接电源", "On AC Power")
        default:         return L("使用电池", "On Battery")
        }
    }

    static func gb(_ bytes: Double) -> String { String(format: "%.1f GB", bytes / 1_073_741_824) }
}

// MARK: - GPU 使用率（读取显卡驱动在 IORegistry 公开的 PerformanceStatistics）
enum GPUMonitor {
    /// 0.0 ~ 1.0；读取失败返回 nil
    static func usage() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let v = stats["Device Utilization %"] as? Int else { continue }
            best = max(best ?? 0, Double(v) / 100)   // 多块显卡时取最忙的
        }
        return best
    }
}

// MARK: - 网络速度
final class NetMonitor {
    private var prev: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    /// 物理网卡（en*，即 Wi-Fi / 有线）累计收发字节；不含 VPN 等虚拟网卡，避免重复计算
    private func totals() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return (0, 0) }
        defer { freeifaddrs(head) }
        var p = head
        while let ifa = p?.pointee {
            defer { p = ifa.ifa_next }
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data, String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
        }
        return (rx, tx)
    }

    /// 两次调用之间的速度（字节/秒）
    func rate() -> (up: Double, down: Double) {
        let now = ProcessInfo.processInfo.systemUptime, t = totals()
        defer { prev = (t.rx, t.tx, now) }
        guard let p = prev, now > p.time else { return (0, 0) }
        let dt = now - p.time
        // 计数器可能回绕（32 位）或网卡重置，出现负值时当作 0
        let down = t.rx >= p.rx ? Double(t.rx - p.rx) / dt : 0
        let up = t.tx >= p.tx ? Double(t.tx - p.tx) / dt : 0
        return (up, down)
    }

    static func format(_ bps: Double, compact: Bool = false) -> String {
        let units = compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = bps, i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1024; i += 1 }
        let num = (i == 0 || v >= 100) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return compact ? num + units[i] : num + " " + units[i]
    }
}

// MARK: - 绘图小工具
func strokeLine(_ pts: [NSPoint], _ w: CGFloat) {
    let p = NSBezierPath()
    p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }
    p.stroke()
}

func punch(_ draw: () -> Void) {   // 在已画内容上挖空
    NSGraphicsContext.current?.compositingOperation = .clear
    draw()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
}

// MARK: - Runner（菜单栏角色，模板图自动适配深浅色菜单栏）
struct Runner {
    let id: String
    let name: String
    let frameCount: Int
    let size: NSSize
    let draw: (_ t: Double) -> Void       // t: 0 ~ 2π

    var displayName: String { let p = name.split(separator: "|").map(String.init); return L(p[0], p.count > 1 ? p[1] : p[0]) }

    func frames() -> [NSImage] {
        (0..<frameCount).map { i in
            let img = NSImage(size: size, flipped: false) { _ in
                NSColor.black.setFill(); NSColor.black.setStroke()
                draw(Double(i) / Double(frameCount) * 2 * .pi)
                return true
            }
            img.isTemplate = true
            return img
        }
    }

    static let all: [Runner] = [cat, coffee]

    // 奔跑小猫
    static let cat = Runner(id: "cat", name: "猫|Cat", frameCount: 12, size: NSSize(width: 28, height: 18)) { t in
        // 奔跑周期：s = +1 身体完全舒展（腾空），s = -1 四腿收拢、拱背
        let s = sin(t), c = cos(t)
        let lift = 0.5 + 0.5 * s                            // 舒展时离地更高
        let shoulder = NSPoint(x: 18.3 + s * 0.7, y: 7.6 + lift - c * 0.5)
        let hip      = NSPoint(x: 9.3 - s * 0.7,  y: 7.8 + lift + c * 0.5)
        let arch = (1 - s) * 1.3                            // 收拢时拱背

        // 腿：大腿 + 小腿 + 爪，dir 决定膝盖朝向
        func leg(_ root: NSPoint, _ angle: Double, knee bend: Double, width: CGFloat) {
            let a1 = angle, a2 = angle + bend
            let k = NSPoint(x: root.x + sin(a1) * 3.4, y: root.y - cos(a1) * 3.4)
            var f = NSPoint(x: k.x + sin(a2) * 3.2, y: k.y - cos(a2) * 3.2)
            f.y = max(0.9, f.y)
            strokeLine([root, k, f], width)
        }
        // 前腿：舒展时向前伸，收拢时向后收，膝盖向后弯
        func frontAngle(_ p: Double) -> Double { sin(p) * 0.6 + 0.25 }
        func backAngle(_ p: Double) -> Double { -sin(p) * 0.6 - 0.25 }
        let fa = frontAngle(t), fb = frontAngle(t - 0.6)
        let ba = backAngle(t), bb = backAngle(t - 0.6)
        // 远侧的腿细一点，制造前后层次
        leg(NSPoint(x: shoulder.x - 1, y: shoulder.y), fb, knee: -0.5 * (1 - sin(t - 0.6)) * 0.6 - 0.1, width: 1.3)
        leg(NSPoint(x: hip.x + 1, y: hip.y), bb, knee: 0.5 + 0.3 * sin(t - 0.6), width: 1.3)

        // 身体：沿脊柱的粗曲线，可伸缩可拱背
        let spine = NSBezierPath()
        spine.lineWidth = 6.2; spine.lineCapStyle = .round
        spine.move(to: hip)
        spine.curve(to: shoulder,
                    controlPoint1: NSPoint(x: hip.x + 3, y: hip.y + arch),
                    controlPoint2: NSPoint(x: shoulder.x - 3, y: shoulder.y + arch))
        spine.stroke()

        // 近侧的腿
        leg(shoulder, fa, knee: -0.5 * (1 - s) * 0.6 - 0.1, width: 1.6)
        leg(hip, ba, knee: 0.5 + 0.3 * s, width: 1.6)

        // 头：跟着肩膀走，落地时轻轻点头
        let hc = NSPoint(x: shoulder.x + 3.4, y: shoulder.y + 2.6 + c * 0.35)
        NSBezierPath(ovalIn: NSRect(x: hc.x - 3.3, y: hc.y - 2.9, width: 6.6, height: 5.8)).fill()
        // 吻部
        NSBezierPath(ovalIn: NSRect(x: hc.x + 1.4, y: hc.y - 2.2, width: 3.0, height: 2.4)).fill()
        // 耳朵（略向后倒，有奔跑感）
        let ears = NSBezierPath()
        ears.move(to: NSPoint(x: hc.x - 2.8, y: hc.y + 1.4)); ears.line(to: NSPoint(x: hc.x - 2.6, y: hc.y + 5.1)); ears.line(to: NSPoint(x: hc.x - 0.2, y: hc.y + 2.6))
        ears.move(to: NSPoint(x: hc.x + 0.2, y: hc.y + 2.7)); ears.line(to: NSPoint(x: hc.x + 1.4, y: hc.y + 5.3)); ears.line(to: NSPoint(x: hc.x + 2.9, y: hc.y + 1.3))
        ears.close(); ears.fill()
        // 眼睛
        punch { NSBezierPath(ovalIn: NSRect(x: hc.x + 0.8, y: hc.y + 0.1, width: 1.5, height: 1.8)).fill() }

        // 尾巴：从臀部甩出的 S 形，波浪沿尾巴传递
        let tail = NSBezierPath()
        tail.lineWidth = 1.5; tail.lineCapStyle = .round
        let tb = NSPoint(x: hip.x - 2.2, y: hip.y + 1.2)
        tail.move(to: tb)
        tail.curve(to: NSPoint(x: tb.x - 5.6, y: tb.y + 3.2 + sin(t - 1.6) * 1.6),
                   controlPoint1: NSPoint(x: tb.x - 2.2, y: tb.y + 0.6 + sin(t - 0.6) * 1.4),
                   controlPoint2: NSPoint(x: tb.x - 3.8, y: tb.y + 1.4 + sin(t - 1.1) * 1.8))
        tail.stroke()
    }

    // 一杯咖啡：圆润杯子 + 细节（杯沿、液面、高光），热气从整个杯口升起、往上收细变淡
    static let coffee = Runner(id: "coffee", name: "咖啡|Coffee", frameCount: 12, size: NSSize(width: 22, height: 22)) { t in
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: 0.5, y: 0)                       // 左右留边

        // 杯子整体放大 1.4 倍（以杯底中心为锚点）
        let K = 1.4, ax = 9.5
        ctx.saveGState()
        ctx.translateBy(x: ax, y: 0); ctx.scaleBy(x: K, y: K); ctx.translateBy(x: -ax, y: 0)

        // 杯身：圆润的碗形
        let cup = NSBezierPath()
        cup.move(to: NSPoint(x: 3.2, y: 9.6))
        cup.line(to: NSPoint(x: 14.8, y: 9.6))
        cup.curve(to: NSPoint(x: 9.0, y: 0.6), controlPoint1: NSPoint(x: 15.0, y: 3.0), controlPoint2: NSPoint(x: 14.0, y: 0.6))
        cup.curve(to: NSPoint(x: 3.2, y: 9.6), controlPoint1: NSPoint(x: 4.0, y: 0.6), controlPoint2: NSPoint(x: 3.0, y: 3.0))
        cup.fill()
        // 杯沿：比杯身略宽的圆角边
        NSBezierPath(roundedRect: NSRect(x: 2.6, y: 9.0, width: 12.8, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
        // 把手
        let handle = NSBezierPath(ovalIn: NSRect(x: 12.6, y: 3.8, width: 4.2, height: 4.2))
        handle.lineWidth = 1.4; handle.stroke()

        // 咖啡液面：杯沿里一圈半透明椭圆
        let surface = NSBezierPath(ovalIn: NSRect(x: 3.7, y: 9.3, width: 10.6, height: 0.8))
        punch { surface.fill() }
        NSColor.black.withAlphaComponent(0.45).setFill(); surface.fill(); NSColor.black.setFill()

        // 高光：杯身左侧一道弯弯的镂空
        punch {
            let shine = NSBezierPath()
            shine.lineWidth = 0.8; shine.lineCapStyle = .round
            shine.move(to: NSPoint(x: 5.0, y: 8.0))
            shine.curve(to: NSPoint(x: 6.6, y: 3.0), controlPoint1: NSPoint(x: 4.6, y: 6.2), controlPoint2: NSPoint(x: 5.2, y: 4.1))
            shine.stroke()
        }
        ctx.restoreGState()

        // 热气：从整个杯口升起，往上收成一缕，越高越淡
        let left = ax + (3.6 - ax) * K, right = ax + (14.4 - ax) * K
        let mid = (left + right) / 2, amp = (right - left) / 2 - 2.2
        let base = 10.4 * K + 0.6, top = 20.6
        let n = 40
        let pts = (0...n).map { i -> NSPoint in
            let u = Double(i) / Double(n)
            return NSPoint(x: mid + sin(u * 1.25 * .pi - t) * (amp + 1) * pow(u, 1.1), y: base + u * (top - base))
        }
        func width(_ u: Double) -> Double { (right - left - 1.0) * pow(1 - u, 2.2) + 1.8 }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // 沿中心线叠扁椭圆，形状平滑不翻折
        let steam = NSBezierPath()
        for i in 0...n {
            let u = Double(i) / Double(n), w = width(u), h = 1.2 + u * 0.4
            steam.append(NSBezierPath(ovalIn: NSRect(x: pts[i].x - w / 2, y: pts[i].y - h / 2, width: w, height: h)))
        }
        ctx.saveGState()
        NSBezierPath(rect: NSRect(x: -1, y: base, width: 24, height: 22)).addClip()
        steam.fill()
        ctx.restoreGState()
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        NSGradient(starting: NSColor.black.withAlphaComponent(0.6), ending: NSColor.black.withAlphaComponent(0.3))!
            .draw(in: NSRect(x: -1, y: base - 2, width: 24, height: 24 - base), angle: 90)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ctx.endTransparencyLayer()
    }
}

// MARK: - 温度（读取系统 HID 温度传感器，无需管理员权限）
@_silgen_name("IOHIDEventSystemClientCreate") private func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func IOHIDEventSystemClientSetMatching(_ c: AnyObject, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func IOHIDEventSystemClientCopyServices(_ c: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func IOHIDServiceClientCopyProperty(_ s: AnyObject, _ k: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func IOHIDServiceClientCopyEvent(_ s: AnyObject, _ t: Int64, _ o: Int32, _ x: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ e: AnyObject, _ f: Int32) -> Double

struct Temps { var soc: Double?, battery: Double?, ssd: Double? }

final class TempMonitor {
    private let client: AnyObject? = {
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        _ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        return c
    }()

    func read() -> Temps {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else { return Temps() }
        var soc: [Double] = [], bat: [Double] = [], ssd: [Double] = []
        for s in services {
            guard let name = IOHIDServiceClientCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let e = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            let v = IOHIDEventGetFloatValue(e, 15 << 16)
            guard v > 0 && v < 150 else { continue }
            if name.hasPrefix("PMU tdie") { soc.append(v) }
            else if name.hasPrefix("gas gauge battery") { bat.append(v) }
            else if name.hasPrefix("NAND") { ssd.append(v) }
        }
        func avg(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        return Temps(soc: soc.max(), battery: avg(bat), ssd: avg(ssd))
    }
}

// MARK: - 电池健康度 / 循环次数
struct BatteryHealth { var health: Double, cycles: Int, designCycles: Int }

extension SystemInfo {
    static func batteryHealth() -> BatteryHealth? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        func int(_ k: String) -> Int? {
            IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        // DesignCapacity / NominalChargeCapacity 在 BatteryData 字典里；顶层可能没有
        let data = IORegistryEntryCreateCFProperty(svc, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] ?? [:]
        func any(_ k: String) -> Int? { int(k) ?? data[k] as? Int }
        guard let design = any("DesignCapacity"), design > 0,
              let nominal = any("NominalChargeCapacity") ?? any("AppleRawMaxCapacity"),
              let cycles = any("CycleCount") else { return nil }
        return BatteryHealth(health: min(Double(nominal) / Double(design), 1), cycles: cycles, designCycles: int("DesignCycleCount9C") ?? 1000)
    }
}

// MARK: - 本机配置（芯片 / 核心数 / 内存 / 硬盘 / 系统版本）
struct MachineSpec {
    var model = "Mac", chip = "", pCores = 0, eCores = 0, gpuCores = 0
    var memoryGB = 0, diskGB = 0, os = ""

    static func sysctlString(_ k: String) -> String {
        var size = 0
        guard sysctlbyname(k, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(k, &buf, &size, nil, 0)
        return String(cString: buf)
    }
    static func sysctlInt(_ k: String) -> Int {
        var v: Int64 = 0, size = MemoryLayout<Int64>.size
        return sysctlbyname(k, &v, &size, nil, 0) == 0 ? Int(v) : 0
    }

    /// 快速读取的部分（同步）
    static func basic() -> MachineSpec {
        var m = MachineSpec()
        m.chip = sysctlString("machdep.cpu.brand_string")
        m.pCores = sysctlInt("hw.perflevel0.physicalcpu")
        m.eCores = sysctlInt("hw.perflevel1.physicalcpu")
        if m.pCores == 0 { m.pCores = sysctlInt("hw.physicalcpu") }
        m.memoryGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let v = ProcessInfo.processInfo.operatingSystemVersion
        m.os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        // GPU 核心数
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS {
            var e = IOIteratorNext(iter)
            while e != 0 {
                if let n = IORegistryEntryCreateCFProperty(e, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                    m.gpuCores = max(m.gpuCores, n)
                }
                IOObjectRelease(e); e = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        // 硬盘：按市售规格取整（500 GB → 512 GB）
        if let total = SystemInfo.storage()?.total {
            let gb = total / 1_000_000_000
            m.diskGB = [128, 256, 512, 1024, 2048, 4096, 8192].first { Double($0) >= gb * 0.95 } ?? Int(gb)
        }
        return m
    }

    /// 机型名称（如 “MacBook Pro”）需要 system_profiler，较慢，放后台读一次
    static func loadModelName(_ done: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPHardwareDataType", "-json"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hw = (json["SPHardwareDataType"] as? [[String: Any]])?.first,
                  let name = hw["machine_name"] as? String else { return }
            DispatchQueue.main.async { done(name) }
        }
    }

    var diskText: String { diskGB >= 1024 ? "\(diskGB / 1024) TB" : "\(diskGB) GB" }
    var shortChip: String { chip.replacingOccurrences(of: "Apple ", with: "") }
    /// 例如 “M2 Pro · 16 GB · 512 GB”
    var summary: String { "\(shortChip) · \(memoryGB) GB · \(diskText)" }
    var detail: String {
        let cpu = eCores > 0 ? L("\(pCores + eCores) 核 CPU（\(pCores)P+\(eCores)E）", "\(pCores + eCores)-core CPU (\(pCores)P+\(eCores)E)")
                             : L("\(pCores) 核 CPU", "\(pCores)-core CPU")
        let gpu = gpuCores > 0 ? " · " + L("\(gpuCores) 核 GPU", "\(gpuCores)-core GPU") : ""
        return cpu + gpu + " · " + os
    }
}

// MARK: - 温度单位
enum TempUnit {
    static var fahrenheit: Bool {
        get { UserDefaults.standard.string(forKey: "tempUnit") == "F" }
        set { UserDefaults.standard.set(newValue ? "F" : "C", forKey: "tempUnit") }
    }
    static func format(_ c: Double, decimals: Int = 1, unit: Bool = true) -> String {
        let v = fahrenheit ? c * 9 / 5 + 32 : c
        return String(format: "%.\(decimals)f", v) + (unit ? (fahrenheit ? "°F" : "°C") : "°")
    }
}

// MARK: - 数据模型：目标值 + 带缓动的显示值（动态效果）
final class StatsModel {
    static var interval = 1.5
    static let historyLength = 120          // 0.5s × 120 = 最近 60 秒

    var cpu = CPULoad(), gpu: Double?, memory = SystemInfo.Memory()
    var storage: (used: Double, total: Double)?
    var battery: (percent: Int, state: String)?, health: BatteryHealth?
    var temps = Temps(), net: (up: Double, down: Double) = (0, 0)
    var cpuHistory: [CPULoad] = [], gpuHistory: [Double] = [], netHistory: [(up: Double, down: Double)] = []
    var memHistory: [Double] = []
    var lastSample = CACurrentMediaTime()

    private var target: [String: Double] = [:]
    private var shown: [String: Double] = [:]

    func set(_ k: String, _ v: Double) { target[k] = v; if shown[k] == nil { shown[k] = v } }
    func v(_ k: String) -> Double { shown[k] ?? 0 }
    func resetShown() { for k in target.keys { shown[k] = 0 } }          // 打开面板时从 0 长出来

    /// 每帧调用：显示值以指数缓动追向目标值
    func tick(dt: Double) {
        let a = 1 - exp(-dt * 7)
        for (k, t) in target { let s = shown[k] ?? t; shown[k] = s + (t - s) * a }
    }

    /// 曲线滚动进度：0 = 刚采样，1 = 下一次采样前
    var scroll: Double { min((CACurrentMediaTime() - lastSample) / Self.interval, 1) }

    func update(cpu: CPULoad, gpu: Double?, memory: SystemInfo.Memory, storage: (used: Double, total: Double)?,
                battery: (percent: Int, state: String)?, health: BatteryHealth?, temps: Temps, net: (up: Double, down: Double)) {
        self.cpu = cpu; self.gpu = gpu; self.memory = memory; self.storage = storage
        self.battery = battery; self.health = health; self.temps = temps; self.net = net
        func push<T>(_ a: inout [T], _ x: T) { a.append(x); if a.count > Self.historyLength { a.removeFirst() } }
        if cpuHistory.isEmpty {   // 首次采样：用当前值填满历史，曲线一打开就是完整的
            cpuHistory = Array(repeating: cpu, count: Self.historyLength)
            gpuHistory = Array(repeating: gpu ?? 0, count: Self.historyLength)
            netHistory = Array(repeating: net, count: Self.historyLength)
            memHistory = Array(repeating: memory.used / memory.total, count: Self.historyLength)
        }
        push(&memHistory, memory.used / memory.total)
        push(&cpuHistory, cpu); push(&gpuHistory, gpu ?? 0); push(&netHistory, net)
        lastSample = CACurrentMediaTime()

        set("cpu", cpu.total); set("sys", cpu.system); set("user", cpu.user); set("idle", cpu.idle)
        set("gpu", gpu ?? 0)
        set("mem", memory.used / memory.total); set("memUsed", memory.used)
        set("app", memory.app / memory.total); set("wired", memory.wired / memory.total); set("comp", memory.compressed / memory.total)
        if let s = storage { set("disk", s.used / s.total) }
        if let b = battery { set("bat", Double(b.percent) / 100) }
        if let h = health { set("health", h.health) }
        if let t = temps.soc { set("tSoc", t) }
        if let t = temps.battery { set("tBat", t) }
        if let t = temps.ssd { set("tSsd", t) }
        set("up", net.up); set("down", net.down)
    }
}

// MARK: - 绘制工具
enum Draw {
    static func text(_ s: String, _ p: NSPoint, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor, right: Bool = false, mono: Bool = false) {
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        str.draw(at: NSPoint(x: right ? p.x - str.size().width : p.x, y: p.y))
    }

    @discardableResult
    static func symbol(_ name: String, _ p: NSPoint, size: CGFloat = 12, color: NSColor = .secondaryLabelColor) -> CGFloat {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return 0 }
        let tinted = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
        tinted.draw(in: NSRect(x: p.x, y: p.y + (16 - img.size.height) / 2, width: img.size.width, height: img.size.height))
        return img.size.width
    }

    /// 卡片标题：图标 + 名称
    static func title(_ icon: String, _ name: String, in w: CGFloat) {
        let iw = symbol(icon, NSPoint(x: 14, y: 12))
        text(name, NSPoint(x: 14 + max(iw, 14) + 6, y: 12), size: 12, weight: .semibold)
    }

    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func level(_ f: Double) -> NSColor { f < 0.7 ? .systemGreen : (f < 0.9 ? .systemYellow : .systemRed) }
    static func tempColor(_ c: Double) -> NSColor { c < 60 ? .systemGreen : (c < 80 ? .systemYellow : .systemRed) }

    static func bar(_ r: NSRect, _ f: Double, _ color: NSColor) {
        let rad = r.height / 2
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad).fill()
        guard f > 0.005 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: max(r.height, r.width * CGFloat(min(f, 1))), height: r.height),
                     xRadius: rad, yRadius: rad).fill()
    }

    /// 平滑滚动的面积图：最新点从右侧滑入；values 为 0~1
    static func area(_ r: NSRect, _ values: [Double], scroll: Double, color: NSColor, line: Bool = false) {
        guard values.count >= 2 else { return }
        let step = r.width / CGFloat(StatsModel.historyLength - 2)
        let shift = step * CGFloat(1 - scroll)
        func pt(_ i: Int) -> NSPoint {
            NSPoint(x: r.maxX - step * CGFloat(values.count - 1 - i) + shift,
                    y: r.maxY - r.height * CGFloat(min(max(values[i], 0), 1)))
        }
        let path = NSBezierPath()
        path.move(to: pt(0))
        for i in 1..<values.count {          // 用中点做平滑曲线
            let p0 = pt(i - 1), p1 = pt(i)
            let mid = NSPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            path.curve(to: mid, controlPoint1: NSPoint(x: (p0.x + mid.x) / 2, y: p0.y), controlPoint2: NSPoint(x: (p0.x + mid.x) / 2, y: mid.y))
            if i == values.count - 1 { path.line(to: p1) }
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).addClip()
        if line {
            path.lineWidth = 1.6; path.lineJoinStyle = .round; color.setStroke(); path.stroke()
        } else {
            let fill = path.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: pt(values.count - 1).x, y: r.maxY + 1))
            fill.line(to: NSPoint(x: pt(0).x, y: r.maxY + 1)); fill.close()
            NSGradient(starting: color.withAlphaComponent(0.55), ending: color.withAlphaComponent(0.08))!.draw(in: fill, angle: 90)
            path.lineWidth = 1.6; color.setStroke(); path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func chartBackground(_ r: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
    }
}

// MARK: - 卡片：一块液态玻璃 + 自绘内容
final class CardView: NSView {
    var drawer: (CGFloat) -> Void = { _ in }
    override var isFlipped: Bool { true }
    static var drawCount = 0
    override func draw(_ dirtyRect: NSRect) { CardView.drawCount += 1; drawer(bounds.width) }
}

// MARK: - 液态玻璃面板（NSPopover 挂在菜单栏图标下，系统负责多屏 / 全屏 / 空间）
final class PanelController: NSObject, NSPopoverDelegate {
    let model: StatsModel
    let popover = NSPopover()
    private var cards: [CardView] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    var onSettings: (NSView) -> Void = { _ in }
    var onVisibilityChange: (Bool) -> Void = { _ in }

    static let width: CGFloat = 340, gap: CGFloat = 10, margin: CGFloat = 10

    init(model: StatsModel) {
        self.model = model
        super.init()
        popover.behavior = .transient          // 点外面自动关闭
        popover.animates = true
        popover.delegate = self
        build()
    }

    private func build() {
        let W = Self.width, g = Self.gap, half = (W - g) / 2
        var layout: [(CGFloat, CGFloat, CGFloat, CGFloat, (CGFloat) -> Void)] = []
        var y: CGFloat = 0
        func add(_ h: CGFloat, _ items: [(CGFloat, CGFloat, (CGFloat) -> Void)]) {
            for (x, w, d) in items { layout.append((x, y, w, h, d)) }
            y += h + g
        }
        add(56,  [(0, W, drawHeader)])
        add(134, [(0, W, drawCPU)])
        add(118, [(0, half, drawGPU), (half + g, half, drawTemps)])
        add(84,  [(0, W, drawMemory)])
        add(118, [(0, half, drawStorage), (half + g, half, drawBattery)])
        add(96,  [(0, W, drawNetwork)])
        let H = y - g, M = Self.margin

        let size = NSSize(width: W + M * 2, height: H + M * 2)
        // 底层：玻璃容器（只放玻璃）；上层：内容（不经过玻璃，避免被折射模糊）
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let container = NSGlassEffectContainerView(frame: root.bounds)
        container.spacing = g
        let glassHolder = NSView(frame: root.bounds)
        let contentLayer = NSView(frame: root.bounds)
        for (x, top, w, h, d) in layout {
            let frame = NSRect(x: M + x, y: M + H - top - h, width: w, height: h)
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = 18
            glass.style = .clear
            glassHolder.addSubview(glass)
            let card = CardView(frame: frame)
            card.drawer = d
            contentLayer.addSubview(card)
            cards.append(card)
            if h == 56 {   // 标题栏里的设置按钮
                let b = NSButton(image: NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")!,
                                 target: self, action: #selector(settingsClicked(_:)))
                b.isBordered = false
                b.contentTintColor = .secondaryLabelColor
                b.frame = NSRect(x: w - 38, y: 16, width: 24, height: 24)
                card.addSubview(b)
            }
        }
        container.contentView = glassHolder
        root.addSubview(container)
        root.addSubview(contentLayer)
        let vc = NSViewController()
        vc.view = root
        popover.contentViewController = vc
        popover.contentSize = size
    }

    @objc private func settingsClicked(_ sender: NSButton) { onSettings(sender) }

    var isVisible: Bool { popover.isShown }

    func show(below button: NSStatusBarButton) {
        model.resetShown()                      // 数字从 0 滚动、条形从空长满
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startTimer()
        onVisibilityChange(true)
    }

    func hide() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) { timer?.invalidate(); timer = nil; onVisibilityChange(false) }

    private func startTimer() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var frameCount = 0
    private func frame() {
        frameCount += 1
        if CommandLine.arguments.contains("--open-panel"), frameCount % 60 == 0 {
            NSLog("panel debug: frames=%d draws=%d shown=%d", frameCount, CardView.drawCount, popover.isShown ? 1 : 0)
        }
        let now = CACurrentMediaTime()
        model.tick(dt: now - lastTick); lastTick = now
        cards.forEach { $0.needsDisplay = true }
    }

    func redrawAll() { cards.forEach { $0.needsDisplay = true; $0.displayIfNeeded() } }

    // MARK: 各卡片绘制
    var spec = MachineSpec.basic()

    private func drawHeader(_ w: CGFloat) {
        let icon = spec.model.contains("Book") ? "laptopcomputer" : (spec.model.contains("iMac") ? "desktopcomputer" : "macmini")
        Draw.symbol(icon, NSPoint(x: 14, y: 10), size: 15, color: .labelColor)
        Draw.text(spec.model, NSPoint(x: 42, y: 8), size: 13, weight: .semibold)
        let mw = NSAttributedString(string: spec.model, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width
        Draw.text(spec.summary, NSPoint(x: 42 + mw + 8, y: 9), size: 12, weight: .medium, color: .secondaryLabelColor)
        Draw.text(spec.detail, NSPoint(x: 42, y: 29), size: 10, color: .secondaryLabelColor)
    }

    private func drawCPU(_ w: CGFloat) {
        let m = model
        Draw.title("cpu", "CPU", in: w)
        Draw.text(Draw.pct(m.v("cpu")), NSPoint(x: w - 14, y: 6), size: 24, weight: .semibold, right: true, mono: true)
        let chart = NSRect(x: 14, y: 44, width: w - 28, height: 56)
        Draw.chartBackground(chart)
        Draw.area(chart, m.cpuHistory.map { $0.system + $0.user }, scroll: m.scroll, color: .systemBlue)
        Draw.area(chart, m.cpuHistory.map { $0.system }, scroll: m.scroll, color: .systemOrange)
        var x: CGFloat = 14
        for (name, key, c) in [("System", "sys", NSColor.systemOrange), ("User", "user", .systemBlue), ("Idle", "idle", .tertiaryLabelColor)] {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 112, width: 7, height: 7)).fill()
            Draw.text("\(name) \(Draw.pct(m.v(key)))", NSPoint(x: x + 11, y: 108), size: 11, color: .secondaryLabelColor, mono: true)
            x += (w - 28) / 3
        }
    }

    private func drawGPU(_ w: CGFloat) {
        let m = model
        Draw.title("cpu.fill", "GPU", in: w)
        Draw.text(m.gpu == nil ? "--" : Draw.pct(m.v("gpu")), NSPoint(x: w - 14, y: 8), size: 20, weight: .semibold, right: true, mono: true)
        let chart = NSRect(x: 14, y: 44, width: w - 28, height: 60)
        Draw.chartBackground(chart)
        Draw.area(chart, m.gpuHistory, scroll: m.scroll, color: .systemGreen)
    }

    private func drawTemps(_ w: CGFloat) {
        let m = model
        Draw.title("thermometer.medium", L("温度", "Temperature"), in: w)
        var y: CGFloat = 40
        for (name, key, has) in [(L("芯片", "SoC"), "tSoc", m.temps.soc != nil), (L("电池", "Battery"), "tBat", m.temps.battery != nil), ("SSD", "tSsd", m.temps.ssd != nil)] {
            let c = m.v(key)
            Draw.text(name, NSPoint(x: 14, y: y), size: 11, color: .secondaryLabelColor)
            Draw.text(has ? TempUnit.format(c) : "--", NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 14, y: y + 17, width: w - 28, height: 4), has ? (c - 20) / 80 : 0, Draw.tempColor(c))
            y += 25
        }
    }

    private func drawMemory(_ w: CGFloat) {
        let m = model
        Draw.title("memorychip", L("内存", "Memory"), in: w)
        Draw.text("\(SystemInfo.gb(m.v("memUsed"))) / \(SystemInfo.gb(m.memory.total))  \(Draw.pct(m.v("mem")))",
                  NSPoint(x: w - 14, y: 13), size: 11, color: .secondaryLabelColor, right: true, mono: true)
        let bar = NSRect(x: 14, y: 40, width: w - 28, height: 10)
        let shape = NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.1).setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        var x = bar.minX
        for (k, c) in [("app", NSColor.systemBlue), ("wired", .systemOrange), ("comp", .systemPurple)] {
            let bw = bar.width * CGFloat(m.v(k))
            c.setFill(); NSRect(x: x, y: bar.minY, width: bw, height: bar.height).fill()
            x += bw
        }
        NSGraphicsContext.restoreGraphicsState()
        var lx: CGFloat = 14
        for (name, v, c) in [("App", m.memory.app, NSColor.systemBlue), (L("联动", "Wired"), m.memory.wired, .systemOrange), (L("压缩", "Compressed"), m.memory.compressed, .systemPurple)] {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: lx, y: 64, width: 7, height: 7)).fill()
            Draw.text("\(name) \(SystemInfo.gb(v))", NSPoint(x: lx + 11, y: 60), size: 10, color: .secondaryLabelColor, mono: true)
            lx += (w - 28) / 3
        }
    }

    private func drawStorage(_ w: CGFloat) {
        let m = model
        Draw.title("internaldrive", L("存储", "Storage"), in: w)
        guard let st = m.storage else { return }
        let f = m.v("disk")
        let center = NSPoint(x: 44, y: 76), r: CGFloat = 26
        let ring = NSBezierPath(); ring.lineWidth = 8
        ring.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        NSColor.labelColor.withAlphaComponent(0.1).setStroke(); ring.stroke()
        let arc = NSBezierPath(); arc.lineWidth = 8; arc.lineCapStyle = .round
        arc.appendArc(withCenter: center, radius: r, startAngle: -90, endAngle: -90 + 360 * CGFloat(f), clockwise: false)
        Draw.level(f).setStroke(); arc.stroke()
        let s = NSAttributedString(string: Draw.pct(f), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        s.draw(at: NSPoint(x: center.x - s.size().width / 2, y: center.y - s.size().height / 2))
        Draw.text(L("已用", "Used"), NSPoint(x: 84, y: 50), size: 10, color: .secondaryLabelColor)
        Draw.text(SystemInfo.gb(st.used), NSPoint(x: 84, y: 63), size: 11, weight: .medium, mono: true)
        Draw.text(L("可用", "Free"), NSPoint(x: 84, y: 80), size: 10, color: .secondaryLabelColor)
        Draw.text(SystemInfo.gb(st.total - st.used), NSPoint(x: 84, y: 93), size: 11, weight: .medium, mono: true)
    }

    private func drawBattery(_ w: CGFloat) {
        let m = model
        Draw.title("battery.100", L("电池", "Battery"), in: w)
        guard let b = m.battery else {
            Draw.text(L("无电池", "No battery"), NSPoint(x: 14, y: 44), size: 11, color: .secondaryLabelColor); return
        }
        let f = m.v("bat")
        let body = NSRect(x: 14, y: 40, width: 46, height: 22)
        let outline = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
        outline.lineWidth = 1.5; NSColor.secondaryLabelColor.setStroke(); outline.stroke()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 2, y: body.midY - 4, width: 3, height: 8), xRadius: 1.5, yRadius: 1.5).fill()
        (b.percent <= 20 ? NSColor.systemRed : (b.percent <= 40 ? .systemYellow : .systemGreen)).setFill()
        NSBezierPath(roundedRect: NSRect(x: body.minX + 3, y: body.minY + 3, width: (body.width - 6) * CGFloat(f), height: body.height - 6),
                     xRadius: 3, yRadius: 3).fill()
        if b.state == "charging" { Draw.symbol("bolt.fill", NSPoint(x: body.midX - 6, y: body.minY + 3), size: 11, color: .white) }
        Draw.text(Draw.pct(f), NSPoint(x: w - 14, y: 41), size: 18, weight: .semibold, right: true, mono: true)
        // 右上角：电池温度；标题旁：供电状态小图标（充电 = 闪电，接电源 = 插头）
        if m.temps.battery != nil {
            Draw.text(TempUnit.format(m.v("tBat")), NSPoint(x: w - 14, y: 13), size: 10, weight: .medium, color: .secondaryLabelColor, right: true, mono: true)
        }
        let titleW = 14 + 22 + 6 + NSAttributedString(string: L("电池", "Battery"), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
        if b.state == "charging" { Draw.symbol("bolt.fill", NSPoint(x: titleW + 4, y: 12), size: 10, color: .systemYellow) }
        else if b.state == "ac"  { Draw.symbol("powerplug.fill", NSPoint(x: titleW + 4, y: 12), size: 10, color: .secondaryLabelColor) }
        if let h = m.health {
            Draw.text(L("健康度", "Health"), NSPoint(x: 14, y: 72), size: 10, color: .secondaryLabelColor)
            Draw.text(Draw.pct(m.v("health")), NSPoint(x: w - 14, y: 71), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 14, y: 87, width: w - 28, height: 4), m.v("health"), m.v("health") >= 0.8 ? .systemGreen : (m.v("health") >= 0.6 ? .systemYellow : .systemRed))
            Draw.text(L("循环次数", "Cycles"), NSPoint(x: 14, y: 96), size: 10, color: .secondaryLabelColor)
            Draw.text("\(h.cycles) / \(h.designCycles)", NSPoint(x: w - 14, y: 95), size: 11, weight: .medium, right: true, mono: true)
        }
    }

    private func drawNetwork(_ w: CGFloat) {
        let m = model
        Draw.title("network", L("网络", "Network"), in: w)
        Draw.text("↓ " + NetMonitor.format(m.v("down")), NSPoint(x: w - 14, y: 13), size: 11, weight: .medium, color: .systemTeal, right: true, mono: true)
        Draw.text("↑ " + NetMonitor.format(m.v("up")), NSPoint(x: w - 120, y: 13), size: 11, weight: .medium, color: .systemPink, right: true, mono: true)
        let chart = NSRect(x: 14, y: 40, width: w - 28, height: 42)
        Draw.chartBackground(chart)
        let peak = max(m.netHistory.map { max($0.up, $0.down) }.max() ?? 0, 10 * 1024)
        Draw.area(chart, m.netHistory.map { $0.down / peak }, scroll: m.scroll, color: .systemTeal)
        Draw.area(chart, m.netHistory.map { $0.up / peak }, scroll: m.scroll, color: .systemPink, line: true)
        Draw.text(L("峰值 ", "Peak ") + NetMonitor.format(peak), NSPoint(x: chart.maxX - 6, y: chart.minY + 3), size: 9, color: .tertiaryLabelColor, right: true, mono: true)
    }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let cpu = CPUMonitor()
    private let netMon = NetMonitor()
    private let tempMon = TempMonitor()
    private let model = StatsModel()
    private lazy var panel = PanelController(model: model)
    private var runner = Runner.all.first { $0.id == UserDefaults.standard.string(forKey: "runner") } ?? Runner.cat
    private lazy var frames = runner.frames()
    private var frameIndex = 0
    private var animTimer: Timer?
    private var sampleTimer: Timer?
    private var usage = 0.0

    /// 菜单栏文字显示什么
    private var barMetric = UserDefaults.standard.string(forKey: "barMetric")
        ?? ((UserDefaults.standard.object(forKey: "showPercent") as? Bool ?? true) ? "cpu" : "none")
    private static var barOptions: [(String, String)] {
        [("cpu", "CPU"), ("gpu", "GPU"), ("memory", L("内存", "Memory")), ("battery", L("电池", "Battery")),
         ("network", L("网络", "Network")), ("temp", L("芯片温度", "SoC Temperature")),
         ("batTemp", L("电池温度", "Battery Temperature")), ("none", L("不显示", "None"))]
    }
    private static var styleOptions: [(String, String)] {
        [("graph+text", L("图表 + 数字", "Graph + Number")), ("graph", L("仅图表", "Graph Only")), ("text", L("仅数字", "Number Only"))]
    }
    private var barStyle = UserDefaults.standard.string(forKey: "barStyle") ?? "graph+text"
    private static let langOptions = [("system", "跟随系统 / System"), ("zh", "中文"), ("en", "English")]
    private let settingsMenu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let button = statusItem.button else { return }
        button.image = frames[0]
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        buildSettingsMenu()
        panel.onSettings = { [weak self] v in self?.popSettings(from: v) }

        panel.onVisibilityChange = { [weak self] open in
            guard let self else { return }
            self.panelOpen = open
            self.startSampling(interval: open ? self.refreshInterval : max(self.refreshInterval, 1.5))
        }
        MachineSpec.loadModelName { [weak self] name in self?.panel.spec.model = name }
        _ = cpu.load(); _ = netMon.rate()
        startSampling(interval: 1.5)
        // 首次采样稍等一下：CPU 占用需要一段时间间隔才算得准，否则历史会被 0 填满
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.sample() }
        scheduleAnimation()

        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.popSettings(from: button) }
        }
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.panel.show(below: button)
                NSLog("panel debug: shown=%d", self.panel.isVisible ? 1 : 0)
            }
        }
    }

    /// 面板打开时 0.5 秒采样一次（接近实时，中间由 60fps 动画补间），关闭时 1.5 秒一次省电
    private func startSampling(interval: Double) {
        StatsModel.interval = interval
        sampleTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        sampleTimer = t
    }

    // MARK: 设置
    private var speedSource = UserDefaults.standard.string(forKey: "speedSource") ?? "cpu"
    private var refreshInterval: Double = {
        let v = UserDefaults.standard.double(forKey: "refreshInterval"); return v > 0 ? v : 0.5
    }()
    private var panelOpen = false
    private var submenus: [String: NSMenu] = [:]

    private func icon(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    /// 单选子菜单：key 用于存储，current 为当前值
    private func choiceMenu(_ key: String, _ title: String, _ symbol: String, _ options: [(String, String)], current: String) -> NSMenuItem {
        let sub = NSMenu()
        for (id, name) in options {
            let item = NSMenuItem(title: name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, id]
            item.state = id == current ? .on : .off
            sub.addItem(item)
        }
        submenus[key] = sub
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = icon(symbol)
        item.submenu = sub
        return item
    }

    private func buildSettingsMenu() {
        settingsMenu.removeAllItems()
        settingsMenu.addItem(NSMenuItem.sectionHeader(title: L("外观", "Appearance")))
        settingsMenu.addItem(choiceMenu("runner", "Runner", "figure.run",
            Runner.all.map { ($0.id, $0.displayName) }, current: runner.id))
        settingsMenu.addItem(choiceMenu("barMetric", L("菜单栏显示", "Menu Bar Shows"), "menubar.rectangle", Self.barOptions, current: barMetric))
        settingsMenu.addItem(choiceMenu("barStyle", L("菜单栏样式", "Menu Bar Style"), "chart.xyaxis.line", Self.styleOptions, current: barStyle))
        settingsMenu.addItem(choiceMenu("speedSource", L("Runner 速度跟随", "Runner Speed Follows"), "speedometer",
            [("cpu", "CPU"), ("gpu", "GPU"), ("memory", L("内存", "Memory"))], current: speedSource))

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem.sectionHeader(title: L("数据", "Data")))
        settingsMenu.addItem(choiceMenu("refreshInterval", L("刷新频率", "Refresh Rate"), "arrow.clockwise",
            [("0.5", L("实时（0.5 秒）", "Real-time (0.5s)")), ("1.0", L("标准（1 秒）", "Standard (1s)")), ("2.0", L("省电（2 秒）", "Power Saving (2s)"))],
            current: String(format: "%.1f", refreshInterval)))
        settingsMenu.addItem(choiceMenu("tempUnit", L("温度单位", "Temperature Unit"), "thermometer.medium",
            [("C", L("摄氏度 °C", "Celsius °C")), ("F", L("华氏度 °F", "Fahrenheit °F"))], current: TempUnit.fahrenheit ? "F" : "C"))
        settingsMenu.addItem(choiceMenu("lang", "语言 / Language", "globe", Self.langOptions, current: Lang.mode))

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem.sectionHeader(title: L("系统", "System")))
        if UserDefaults.standard.object(forKey: "didSetupLogin") == nil {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
        }
        let loginItem = NSMenuItem(title: L("开机自动启动", "Launch at Login"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.image = icon("power")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settingsMenu.addItem(loginItem)
        let am = NSMenuItem(title: L("打开活动监视器", "Open Activity Monitor"), action: #selector(openActivityMonitor), keyEquivalent: "a")
        am.target = self; am.image = icon("waveform.path.ecg")
        settingsMenu.addItem(am)
        let about = NSMenuItem(title: L("关于 MenuRunner", "About MenuRunner"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self; about.image = icon("info.circle")
        settingsMenu.addItem(about)

        settingsMenu.addItem(.separator())
        let quit = NSMenuItem(title: L("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = icon("xmark.circle")
        settingsMenu.addItem(quit)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        let (key, id) = (pair[0], pair[1])
        submenus[key]?.items.forEach { $0.state = (($0.representedObject as? [String])?.last == id) ? .on : .off }
        switch key {
        case "runner":
            guard let r = Runner.all.first(where: { $0.id == id }) else { return }
            runner = r; frames = r.frames(); frameIndex = 0
            UserDefaults.standard.set(id, forKey: "runner")
            updateStatusImage()
        case "barMetric":
            barMetric = id; UserDefaults.standard.set(id, forKey: "barMetric"); sample()
        case "barStyle":
            barStyle = id; UserDefaults.standard.set(id, forKey: "barStyle"); sample()
        case "speedSource":
            speedSource = id; UserDefaults.standard.set(id, forKey: "speedSource"); sample()
        case "refreshInterval":
            refreshInterval = Double(id) ?? 0.5
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            startSampling(interval: panelOpen ? refreshInterval : max(refreshInterval, 1.5))
        case "tempUnit":
            TempUnit.fahrenheit = id == "F"; sample(); panel.redrawAll()
        case "lang":
            Lang.mode = id; buildSettingsMenu(); panel.redrawAll(); sample()
        default: break
        }
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MenuRunner",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .credits: NSAttributedString(string: L("菜单栏里的小跑者 + 系统监控", "A tiny menu bar runner + system monitor"),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.hide()
            popSettings(from: sender)
        } else if panel.isVisible {
            panel.hide()
        } else {
            panel.show(below: sender)
        }
    }

    private func popSettings(from view: NSView) {
        settingsMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private func sample() {
        let l = cpu.load()
        usage = l.total
        let g = GPUMonitor.usage(), m = SystemInfo.memory(), n = netMon.rate(), t = tempMon.read()
        switch speedSource {           // Runner 跟随哪个指标变快
        case "gpu":    usage = g ?? 0
        case "memory": usage = m.used / m.total
        default:       usage = l.total
        }
        let bat = SystemInfo.battery()
        model.update(cpu: l, gpu: g, memory: m, storage: SystemInfo.storage(), battery: bat,
                     health: SystemInfo.batteryHealth(), temps: t, net: n)
        let pct = Draw.pct
        let title: String
        switch barMetric {
        case "gpu":     title = " " + (g.map(pct) ?? "--")
        case "memory":  title = " " + pct(m.used / m.total)
        case "battery": title = bat.map { " \($0.percent)%" } ?? " --"
        case "network": title = " ↓\(NetMonitor.format(n.down, compact: true)) ↑\(NetMonitor.format(n.up, compact: true))"
        case "temp":    title = t.soc.map { " " + TempUnit.format($0, decimals: 0, unit: false) } ?? " --"
        case "batTemp": title = t.battery.map { " " + TempUnit.format($0, decimals: 1, unit: false) } ?? " --"
        case "none":    title = ""
        default:        title = " " + pct(l.total)
        }
        statusItem.button?.title = barStyle == "graph" ? "" : title
        updateStatusImage()
        scheduleAnimation()
    }

    // MARK: 菜单栏动态小图标（单色模板图，随深浅色菜单栏自动变色）
    private func updateStatusImage() {
        let rf = frames[frameIndex]
        guard barStyle != "text", barMetric != "none" else { statusItem.button?.image = rf; return }
        let gw: CGFloat
        switch barMetric {
        case "battery": gw = 22
        case "temp", "batTemp": gw = 9
        default: gw = 26
        }
        let h = max(rf.size.height, 18)
        let size = NSSize(width: rf.size.width + 4 + gw, height: h)
        let img = NSImage(size: size, flipped: false) { [weak self] _ in
            rf.draw(in: NSRect(x: 0, y: (h - rf.size.height) / 2, width: rf.size.width, height: rf.size.height))
            self?.drawMini(in: NSRect(x: rf.size.width + 4, y: (h - 14) / 2, width: gw, height: 14))
            return true
        }
        img.isTemplate = true
        statusItem.button?.image = img
    }

    private func drawMini(in r: NSRect) {
        let m = model
        NSColor.black.setFill(); NSColor.black.setStroke()
        // 迷你走势图：最近 24 个点，平滑滚动
        func spark(_ values: [Double], line: [Double]? = nil) {
            let frame = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            frame.lineWidth = 1
            NSColor.black.withAlphaComponent(0.45).setStroke(); frame.stroke()
            let inner = r.insetBy(dx: 1.5, dy: 1.5)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: 1.5, yRadius: 1.5).addClip()
            let n = 24, step = inner.width / CGFloat(n - 2)
            let shift = step * CGFloat(1 - m.scroll)
            func path(_ v: [Double]) -> NSBezierPath {
                let vs = Array(v.suffix(n))
                let p = NSBezierPath()
                for (i, x) in vs.enumerated() {
                    let pt = NSPoint(x: inner.maxX - step * CGFloat(vs.count - 1 - i) + shift,
                                     y: inner.minY + inner.height * CGFloat(min(max(x, 0), 1)))
                    i == 0 ? p.move(to: pt) : p.line(to: pt)
                }
                return p
            }
            guard values.count >= 2 else { NSGraphicsContext.restoreGraphicsState(); return }   // 首次采样前没有数据
            let area = path(values)
            area.line(to: NSPoint(x: inner.maxX + step, y: inner.minY))
            area.line(to: NSPoint(x: inner.minX - step * 2, y: inner.minY))
            area.close()
            NSColor.black.withAlphaComponent(line == nil ? 1 : 0.55).setFill(); area.fill()
            if let line, line.count >= 2 {
                let l = path(line); l.lineWidth = 1.2; l.lineJoinStyle = .round
                NSColor.black.setStroke(); l.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        // 小温度计：竖条 + 底部圆球，按温度填充（20–100°C）
        func thermo(_ c: Double?) {
            let tube = NSRect(x: r.midX - 2, y: r.minY + 3, width: 4, height: r.height - 3)
            let outline = NSBezierPath(roundedRect: tube, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1; outline.stroke()
            NSBezierPath(ovalIn: NSRect(x: r.midX - 3.5, y: r.minY, width: 7, height: 7)).fill()
            let f = CGFloat(min(max(((c ?? 20) - 20) / 80, 0), 1))
            NSRect(x: tube.minX + 1, y: tube.minY, width: tube.width - 2, height: (tube.height - 1) * f).fill()
        }
        switch barMetric {
        case "gpu":    spark(m.gpuHistory)
        case "memory": spark(m.memHistory)
        case "network":
            let peak = max(m.netHistory.suffix(24).map { max($0.up, $0.down) }.max() ?? 0, 10 * 1024)
            spark(m.netHistory.map { $0.down / peak }, line: m.netHistory.map { $0.up / peak })
        case "battery":
            let body = NSRect(x: r.minX, y: r.midY - 5, width: r.width - 3, height: 10)
            let o = NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            o.lineWidth = 1; o.stroke()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.5, y: r.midY - 2, width: 1.8, height: 4), xRadius: 0.8, yRadius: 0.8).fill()
            let f = CGFloat(Double(m.battery?.percent ?? 0) / 100)
            NSBezierPath(roundedRect: NSRect(x: body.minX + 2, y: body.minY + 2, width: (body.width - 4) * f, height: body.height - 4),
                         xRadius: 1.2, yRadius: 1.2).fill()
            if m.battery?.state == "charging" {   // 充电闪电：挖空
                NSGraphicsContext.current?.compositingOperation = .clear
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: body.midX + 1, y: body.maxY - 1)); bolt.line(to: NSPoint(x: body.midX - 2.5, y: body.midY - 0.5))
                bolt.line(to: NSPoint(x: body.midX, y: body.midY - 0.5)); bolt.line(to: NSPoint(x: body.midX - 1, y: body.minY + 1))
                bolt.line(to: NSPoint(x: body.midX + 2.5, y: body.midY + 0.5)); bolt.line(to: NSPoint(x: body.midX, y: body.midY + 0.5))
                bolt.close(); bolt.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }
        case "temp":    thermo(m.temps.soc)
        case "batTemp": thermo(m.temps.battery)
        default:        spark(m.cpuHistory.map { $0.total })
        }
    }

    /// CPU 越高跑得越快：0% → 0.2s/帧，100% → 0.03s/帧
    private func scheduleAnimation() {
        let interval = 0.2 - 0.17 * min(max(usage, 0), 1)
        animTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frames.count
            self.updateStatusImage()
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let svc = SMAppService.mainApp
        do { if svc.status == .enabled { try svc.unregister() } else { try svc.register() } }
        catch { NSLog("Login item error: \(error)") }
        if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        sender.state = svc.status == .enabled ? .on : .off
    }
}

// MARK: - 调试命令
// MenuRunner --stats           打印系统信息
// MenuRunner --preview out.png 导出所有 runner 的帧图
if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--stats" {
    let c = CPUMonitor(), nm = NetMonitor(); _ = c.load(); _ = nm.rate()
    Thread.sleep(forTimeInterval: 1)
    let l = c.load(), nr = nm.rate(), m = SystemInfo.memory(), t = TempMonitor().read()
    print(String(format: "CPU %.0f%%  system %.0f%%  user %.0f%%  idle %.0f%%", l.total * 100, l.system * 100, l.user * 100, l.idle * 100))
    print("gpu", GPUMonitor.usage().map(Draw.pct) ?? "nil")
    print("memory", SystemInfo.gb(m.used), "/", SystemInfo.gb(m.total))
    print("storage", SystemInfo.storage().map { "\(SystemInfo.gb($0.used)) / \(SystemInfo.gb($0.total))" } ?? "nil")
    print("battery", SystemInfo.battery().map { "\($0.percent)% \(SystemInfo.stateText($0.state))" } ?? "nil")
    print("health", SystemInfo.batteryHealth().map { "\(Draw.pct($0.health)) cycles \($0.cycles)/\($0.designCycles)" } ?? "nil")
    print("temps soc", t.soc.map { String(format: "%.1f", $0) } ?? "nil", "battery", t.battery.map { String(format: "%.1f", $0) } ?? "nil",
          "ssd", t.ssd.map { String(format: "%.1f", $0) } ?? "nil")
    print("network up", NetMonitor.format(nr.up), "down", NetMonitor.format(nr.down))
    exit(0)
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--preview" {
    let sc = 8.0, w = Runner.all.map { $0.size.width * CGFloat($0.frameCount) }.max()!
    let rowH = 22.0, rows = Double(Runner.all.count)
    let sheet = NSImage(size: NSSize(width: w * sc, height: rowH * sc * rows), flipped: true) { _ in
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w * sc, height: rowH * sc * rows).fill()
        for (row, r) in Runner.all.enumerated() {
            for (i, f) in r.frames().enumerated() {
                f.draw(in: NSRect(x: Double(i) * r.size.width * sc, y: Double(row) * rowH * sc, width: r.size.width * sc, height: r.size.height * sc),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        return true
    }
    let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不显示 Dock 图标
app.run()
