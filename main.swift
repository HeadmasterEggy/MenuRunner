import AppKit
import SwiftUI
import QuartzCore
import ServiceManagement
import IOKit.ps
import IOKit
import SystemConfiguration

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

    private static var storageCache: (value: (used: Double, total: Double)?, at: CFTimeInterval) = (nil, -1000)

    /// 磁盘用量缓存 30 秒（每次查询 ~20ms，而且不会秒级变化）
    static func storage() -> (used: Double, total: Double)? {
        let now = CACurrentMediaTime()
        if now - storageCache.at < 30, let v = storageCache.value { return v }
        let v = storageUncached(); storageCache = (v, now); return v
    }

    private static func storageUncached() -> (used: Double, total: Double)? {
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

    /// 续航估算：(标签, 时间文本)。放电 → 预计可用；充电 → 充满还需；接电源已充满 → 已接电源
    static func batteryTime() -> (label: String, value: String)? {
        guard let b = battery() else { return nil }
        func fmt(_ minutes: Int) -> String {
            minutes >= 60 ? L("\(minutes / 60) 小时 \(minutes % 60) 分", "\(minutes / 60)h \(minutes % 60)m") : L("\(minutes) 分钟", "\(minutes) min")
        }
        if b.state == "charging" {
            var mins = -1
            if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
                for ps in list {
                    if let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                       let t = d[kIOPSTimeToFullChargeKey] as? Int { mins = t }
                }
            }
            return (L("充满还需", "Until full"), mins > 0 ? fmt(mins) : L("计算中…", "Calculating…"))
        }
        if b.state == "ac" { return (L("续航", "Battery"), L("已接电源", "On AC power")) }
        let left = (L("预计可用", "Time left"))
        // 1. 电源信息里的“距离耗尽分钟数”（-1 = 还在估算）
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                if let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                   let m = d[kIOPSTimeToEmptyKey] as? Int, m > 0 { return (left, fmt(m)) }
            }
        }
        // 2. 系统估算（秒）
        let est = IOPSGetTimeRemainingEstimate()
        if est > 0 { return (left, fmt(Int(est / 60))) }
        // 3. 电池自己上报的平均剩余时间（刚拔电时系统估算还没出来，这里往往已经有值）
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        defer { if svc != 0 { IOObjectRelease(svc) } }
        func num(_ k: String) -> NSNumber? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber }
        for k in ["AvgTimeToEmpty", "TimeRemaining"] {
            if let m = num(k)?.intValue, m > 0, m < 65535 { return (left, fmt(m)) }
        }
        // 4. 自己算：满充容量 × 当前百分比 ÷ 放电电流
        let ma = Double(Int32(truncatingIfNeeded: num("InstantAmperage")?.int64Value ?? num("Amperage")?.int64Value ?? 0))
        let data = IORegistryEntryCreateCFProperty(svc, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        let full = num("NominalChargeCapacity")?.doubleValue ?? (data?["NominalChargeCapacity"] as? NSNumber)?.doubleValue
        if let full, ma < -50 {
            return (left, "≈ " + fmt(Int(full * Double(b.percent) / 100 / -ma * 60)))
        }
        return (L("预计可用", "Time left"), L("计算中…", "Calculating…"))
    }

    /// 内存压力（与活动监视器一致）：1 正常，2 偏高，4 紧张
    static func memoryPressure() -> Int {
        var v: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &v, &size, nil, 0) == 0 ? Int(v) : 1
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

    /// GPU 正在使用的（共享）内存，字节
    static func memoryInUse() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var total: Double?
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any], let v = (stats["In use system memory"] as? NSNumber)?.doubleValue {
                total = (total ?? 0) + v
            }
        }
        return total
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
    /// 从 MenuRunner 启动以来累计的上传 / 下载字节
    private(set) var totalUp: Double = 0, totalDown: Double = 0

    func rate() -> (up: Double, down: Double) {
        let now = ProcessInfo.processInfo.systemUptime, t = totals()
        defer { prev = (t.rx, t.tx, now) }
        guard let p = prev, now > p.time else { return (0, 0) }
        let dt = now - p.time
        // 计数器可能回绕（32 位）或网卡重置，出现负值时当作 0
        let down = t.rx >= p.rx ? Double(t.rx - p.rx) / dt : 0
        let up = t.tx >= p.tx ? Double(t.tx - p.tx) / dt : 0
        totalDown += down * dt; totalUp += up * dt
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
    var template = true                    // false = 彩色图（不随菜单栏变色）
    var levels = 1                         // >1：按占用率分档，每档一套帧（如心电图档位越高心跳越密）
    let draw: (_ t: Double, _ level: Int) -> Void       // t: 0 ~ 2π；level: 0 ..< levels

    var displayName: String { let p = name.split(separator: "|").map(String.init); return L(p[0], p.count > 1 ? p[1] : p[0]) }

    /// 每帧只画一次，存成 2x 位图（之前每次显示都会重画，菜单栏动画一直占 CPU）
    /// appearance：彩色 runner 里用到的动态颜色（如 labelColor）按它解析
    func frames(appearance: NSAppearance? = nil, level: Int = 0) -> [NSImage] {
        (0..<frameCount).map { i in
            let scale: CGFloat = 2
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let render = {
                NSColor.black.setFill(); NSColor.black.setStroke()
                self.draw(Double(i) / Double(self.frameCount) * 2 * .pi, level)
            }
            if let appearance { appearance.performAsCurrentDrawingAppearance(render) } else { render() }
            NSGraphicsContext.restoreGraphicsState()
            let img = NSImage(size: size)
            img.addRepresentation(rep)
            img.isTemplate = template
            return img
        }
    }

    static let all: [Runner] = [coffee, rocketCat, fan, pulse, bars]

    // 橘猫火箭（原创彩色像素画）：橘猫骑着小火箭，尾焰闪烁，星星一闪一闪；占用率越高尾焰越长、闪得越快
    static let rocketCat = Runner(id: "rocket", name: "橘猫火箭|Rocket Cat", frameCount: 12, size: NSSize(width: 36, height: 20), template: false, levels: 3) { t, level in
        let W = 36, H = 20
        let f12 = Int((t / (2 * .pi) * 12).rounded()) % 12
        let f = f12 % 6                                  // 颠簸、尾巴：每帧走 1 步
        let g = Int(Double(f12) * [1, 1.5, 2][level]) % 6   // 尾焰、星星：每帧走 1 / 1.5 / 2 步（12 帧走 12 / 18 / 24 步，循环无缝）
        func c(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        let orange = c(0.97, 0.60, 0.20), stripe = c(0.82, 0.40, 0.10), white = c(0.99, 0.97, 0.93)
        let pink = c(0.99, 0.56, 0.66), eye = c(0.10, 0.09, 0.12), outline = c(0.16, 0.13, 0.18)
        let hull = c(0.90, 0.92, 0.96), hullShade = c(0.66, 0.70, 0.79), red = c(0.92, 0.22, 0.24)
        let glass = c(0.40, 0.74, 0.99), glassDark = c(0.16, 0.38, 0.74), nozzle = c(0.38, 0.38, 0.44)
        let flameY = c(1.0, 0.90, 0.30), flameO = c(1.0, 0.56, 0.16), flameR = c(0.96, 0.27, 0.22)

        var grid = [[NSColor?]](repeating: [NSColor?](repeating: nil, count: W), count: H)
        let bob = f % 2 + 1                              // 整体上下颠簸 1 格（+1 给顶部描边留空间）
        func set(_ x: Int, _ y: Int, _ col: NSColor) {
            let yy = y + bob
            if x >= 0 && x < W && yy >= 0 && yy < H { grid[yy][x] = col }
        }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ col: NSColor) {
            for y in y0...y1 { for x in x0...x1 { set(x, y, col) } }
        }

        // —— 火箭（朝右）
        rect(12, 10, 29, 14, hull)
        rect(12, 14, 29, 14, hullShade)                  // 底部阴影
        for (y, len) in [(10, 2), (11, 3), (12, 4), (13, 3), (14, 2)] { rect(30, y, 29 + len, y, red) }   // 尖头
        rect(12, 7, 14, 9, red); set(15, 9, red)         // 上尾翼
        rect(12, 15, 14, 16, red); set(15, 15, red)      // 下尾翼
        rect(10, 11, 11, 13, nozzle)                     // 喷口
        rect(24, 11, 26, 13, glassDark); set(25, 12, glass); set(24, 11, glass)   // 舷窗

        // —— 橘猫（坐在火箭上，面朝右）
        rect(16, 4, 22, 9, orange)                       // 身体
        for x in [17, 19] { rect(x, 4, x, 6, stripe) }   // 条纹
        rect(20, 6, 22, 9, white)                        // 肚皮
        rect(21, 1, 27, 6, orange)                       // 头
        set(21, 0, orange); set(22, 0, orange); set(26, 0, orange); set(27, 0, orange)   // 耳朵
        set(22, 1, pink); set(26, 1, pink)               // 耳朵内侧
        set(24, 1, stripe); set(24, 2, stripe)           // 额头条纹
        set(23, 3, eye); set(26, 3, eye)                 // 眼睛
        rect(23, 4, 26, 5, white)                        // 嘴巴
        set(24, 4, pink)                                 // 鼻子
        set(22, 4, pink); set(27, 4, pink)               // 腮红
        rect(22, 9, 24, 9, white)                        // 前爪抱住火箭
        // 尾巴：向后飘，随帧上下甩
        let tailY = [5, 4, 4, 5, 6, 6][f]
        set(15, 7, orange); set(14, tailY + 1, orange); set(13, tailY, orange); set(12, tailY, stripe)

        // —— 自动描边：实心像素四周的空格画深色轮廓
        let solid = grid.map { $0.map { $0 != nil } }
        for y in 0..<H { for x in 0..<W where !solid[y][x] {
            let n = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            if n.contains(where: { $0.0 >= 0 && $0.0 < W && $0.1 >= 0 && $0.1 < H && solid[$0.1][$0.0] }) { grid[y][x] = outline }
        } }

        // —— 尾焰（不描边）：黄 → 橙 → 红，长度闪动；高档长短交替更猛，上下再加两道
        let len = [[4, 5, 5, 6, 5, 4], [6, 8, 7, 9, 6, 8], [10, 7, 10, 8, 10, 7]][level][g]
        let rows = level == 2 ? [(10, 4), (11, 1), (12, 0), (13, 1), (14, 4)] : [(11, 2), (12, 0), (13, 2)]
        for (dy, short) in rows {
            let l = len - short
            for i in 0..<max(l, 0) {
                let x = 9 - i
                let col = i < l / 3 ? flameY : (i < l * 2 / 3 ? flameO : flameR)
                if x >= 0 && grid[dy + bob][x] == nil { grid[dy + bob][x] = col }
            }
        }

        // —— 画像素
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShouldAntialias(false)
        for y in 0..<H { for x in 0..<W { if let col = grid[y][x] { col.setFill(); NSRect(x: x, y: H - 1 - y, width: 1, height: 1).fill() } } }

        // —— 星星：一闪一闪，亮时是十字
        for (sx, sy, ph) in [(3, 3, 0), (32, 2, 2), (6, 18, 4), (34, 17, 1)] {
            let phase = (g + ph) % 6
            guard phase < 4 else { continue }
            let col = NSColor(srgbRed: 1, green: 0.78, blue: 0.18, alpha: phase == 1 ? 1 : 0.75)   // 暖黄，浅色背景也看得见
            col.setFill()
            NSRect(x: sx, y: H - 1 - sy, width: 1, height: 1).fill()
            if phase == 1 {
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { NSRect(x: sx + dx, y: H - 1 - sy - dy, width: 1, height: 1).fill() }
            }
        }
    }

    // 一杯咖啡：圆润杯子 + 细节（杯沿、液面、高光），热气从整个杯口升起、往上收细变淡；占用率越高热气越多、升得越快
    static let coffee = Runner(id: "coffee", name: "咖啡|Coffee", frameCount: 24, size: NSSize(width: 22, height: 22), levels: 3) { t, level in
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
        let base = 10.4 * K + 0.6, top = [17.5, 20.6, 21.6][level]
        let n = 40, tt = t * [2, 3, 4][level]                 // 24 帧摆动 2 / 3 / 4 次（每帧 ×1 / ×1.5 / ×2），循环无缝
        // 一缕热气：沿中心线叠扁椭圆，形状平滑不翻折；高档两侧再各冒一缕细的
        func wisp(_ dx: Double, _ ph: Double, _ ws: Double, _ topY: Double) -> NSBezierPath {
            let path = NSBezierPath()
            for i in 0...n {
                let u = Double(i) / Double(n)
                let x = mid + dx * (1 - u * 0.5) + sin(u * 1.25 * .pi - tt + ph) * (amp + 1) * ws * pow(u, 1.1), y = base + u * (topY - base)
                let w = ((right - left - 1.0) * pow(1 - u, 2.2) + 1.8) * ws, h = 1.2 + u * 0.4
                path.append(NSBezierPath(ovalIn: NSRect(x: x - w / 2, y: y - h / 2, width: w, height: h)))
            }
            return path
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let steam = wisp(0, 0, 1, top)
        if level == 2 { steam.append(wisp(-4.2, .pi, 0.45, top - 2)); steam.append(wisp(4.2, .pi / 2, 0.45, top - 3)) }
        ctx.saveGState()
        NSBezierPath(rect: NSRect(x: -1, y: base, width: 24, height: 22)).addClip()
        steam.fill()
        ctx.restoreGState()
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        let alpha = [0.4, 0.6, 0.8][level]
        NSGradient(starting: NSColor.black.withAlphaComponent(alpha), ending: NSColor.black.withAlphaComponent(alpha / 2))!
            .draw(in: NSRect(x: -1, y: base - 2, width: 24, height: 24 - base), angle: 90)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ctx.endTransparencyLayer()
    }
}

// MARK: - 更多 Runner（矢量绘制，非像素）
private func pt(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x, y: y) }

extension Runner {
    // 小风扇：四片弯叶片顺时针转，带淡淡的残影；占用率越高每帧转得越多（×1 / ×1.5 / ×2）、残影越长
    static let fan = Runner(id: "fan", name: "风扇|Fan", frameCount: 24, size: NSSize(width: 20, height: 20), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        let ring = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 18, height: 18))
        ring.lineWidth = 1.3; ring.stroke()
        for k in 0..<4 {
            let trail: [(Double, Double)] = [[(0.35, 0.22)], [(0.6, 0.12), (0.3, 0.26)], [(0.9, 0.08), (0.6, 0.16), (0.3, 0.3)]][level]
            for (off, a) in trail + [(0.0, 1.0)] {             // 先画残影，再画叶片
                ctx.saveGState()
                ctx.translateBy(x: 10, y: 10)
                ctx.rotate(by: CGFloat(-t / 2 * [1, 1.5, 2][level] + Double(k) * .pi / 2 + off))   // 4 重对称：24 帧转 1/2、3/4、1 圈
                let b = NSBezierPath()
                b.move(to: pt(-0.8, 1.6))
                b.curve(to: pt(-0.2, 7.6), controlPoint1: pt(-2.6, 4.2), controlPoint2: pt(-2.4, 7.0))
                b.curve(to: pt(3.8, 5.6), controlPoint1: pt(1.6, 8.6), controlPoint2: pt(3.6, 7.6))
                b.curve(to: pt(0.9, 1.6), controlPoint1: pt(3.6, 4.0), controlPoint2: pt(2.0, 2.4))
                b.close()
                NSColor.black.withAlphaComponent(a).setFill(); b.fill()
                ctx.restoreGState()
            }
        }
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.6, y: 7.6, width: 4.8, height: 4.8)).fill()            // 轴心
        punch { NSBezierPath(ovalIn: NSRect(x: 9.1, y: 9.1, width: 1.8, height: 1.8)).fill() }
    }

    // 心电图：波形向左滚动，左侧渐隐，右端一个亮点；占用率越高档位越高，窗口里的心跳越密（1 / 2 / 3 拍）、滚得越快（每帧 ×1 / ×1.5 / ×2），每拍高低不一，档位越高峰越高
    static let pulse = Runner(id: "pulse", name: "心电图|Heartbeat", frameCount: 45, size: NSSize(width: 30, height: 18), levels: 3) { t, level in
        let ctx = NSGraphicsContext.current!.cgContext
        // 一圈帧滚过 90×m 个单位（m = 1 / 1.5 / 2）= 3 / 9 / 18 拍，循环无缝；拍子变密时波形横向压缩
        let m = [1, 1.5, 2][level]
        let period = 30.0 / Double(level + 1), sx = [1, 0.6, 0.42][level], off = t / (2 * .pi) * 90 * m, base = 5.0
        let beats = Int(3 * m * Double(level + 1))
        let amps = [1.0, 0.8, 0.92, 0.72, 0.97, 0.84, 0.88, 0.76, 0.94]   // 每拍的幅度
        let scale = [0.7, 0.9, 1.15][level]                                 // 档位整体高度
        let keys: [(Double, Double)] = [(0, 0), (4, 0), (5.5, 1.3), (7, 0), (10, 0), (11, -1.3), (12.6, 9.5), (14.2, -3.2),
                                        (15.6, 0), (18, 0), (20, 2.0), (22.5, 0)].map { ($0.0 * sx, $0.1) } + [(period, 0)]
        func ecg(_ x: Double) -> Double {
            let p = x + off, u = p.truncatingRemainder(dividingBy: period)
            let amp = scale * amps[Int(p / period) % beats % amps.count]
            for i in 0..<(keys.count - 1) where u >= keys[i].0 && u <= keys[i + 1].0 {
                let (a, va) = keys[i], (b, vb) = keys[i + 1]
                return base + amp * (va + (vb - va) * (u - a) / (b - a))
            }
            return base
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let line = NSBezierPath()
        line.lineWidth = 1.5; line.lineCapStyle = .round; line.lineJoinStyle = .round
        line.move(to: pt(1.5, ecg(0)))
        for i in 1...108 { let x = Double(i) * 0.25; line.line(to: pt(x + 1.5, ecg(x))) }
        line.stroke()
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        NSGradient(colorsAndLocations: (NSColor.black.withAlphaComponent(0), 0), (NSColor.black, 0.55), (NSColor.black, 1))!
            .draw(in: NSRect(x: 0, y: 0, width: 30, height: 18), angle: 0)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ctx.endTransparencyLayer()
        let y = ecg(27)
        NSBezierPath(ovalIn: NSRect(x: 27.1, y: y - 1.4, width: 2.8, height: 2.8)).fill()
    }

    // 音波：五根圆头竖条随节奏跳动；占用率越高跳得越高、越密
    static let bars = Runner(id: "bars", name: "音波|Sound Wave", frameCount: 24, size: NSSize(width: 22, height: 18), levels: 3) { t, level in
        let phase = [0, 2.1, 4.0, 1.1, 3.1], k = [1.0, 2, 1, 3, 2], f = [2.0, 3, 4][level]   // 24 帧：频率 ×2 / ×3 / ×4 取整，每帧 ×1 / ×1.5 / ×2，循环无缝
        let span = [7.0, 10.5, 14.5][level]                   // 跳动幅度
        for i in 0..<5 {
            let v = 0.5 + 0.32 * sin(k[i] * f * t + phase[i]) + 0.18 * sin((k[i] + 1) * f * t + phase[i] * 1.7)
            let h = 2.6 + v * span
            NSBezierPath(roundedRect: NSRect(x: 1.6 + Double(i) * 3.9, y: 9 - h / 2, width: 2.8, height: h), xRadius: 1.4, yRadius: 1.4).fill()
        }
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
    static let shared = TempMonitor()
    private let client: AnyObject? = {
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        _ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        return c
    }()

    /// 所有传感器（同名取平均），按名称排序
    /// 传感器列表（含名字）缓存 30 秒：每次重新枚举 + 取名字要 ~80ms，是采样里最贵的一步
    private var cached: [(AnyObject, String)] = []
    private var cachedAt: CFTimeInterval = -1000
    private func sensorList() -> [(AnyObject, String)] {
        let now = CACurrentMediaTime()
        if now - cachedAt < 30, !cached.isEmpty { return cached }
        guard let client, let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        cached = services.compactMap { s in
            (IOHIDServiceClientCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String).map { (s, $0) }
        }
        cachedAt = now
        return cached
    }

    func readAll() -> [(String, Double)] {
        var g: [String: [Double]] = [:]
        for (s, name) in sensorList() {
            guard let e = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            let v = IOHIDEventGetFloatValue(e, 15 << 16)
            if v > 0 && v < 150 { g[name, default: []].append(v) }
        }
        return g.map { ($0.key, $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    func read() -> Temps {
        var soc: [Double] = [], bat: [Double] = [], ssd: [Double] = []
        for (s, name) in sensorList() where name.hasPrefix("PMU tdie") || name.hasPrefix("gas gauge battery") || name.hasPrefix("NAND") {
            guard let e = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
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

// MARK: - 各应用内存占用（与活动监视器“内存”列同口径：phys_footprint）
struct AppMemory { var name: String, path: String?, bytes: UInt64, processes: Int }

enum ProcessMemory {
    /// 按应用汇总（同一 .app 下的 Helper 进程合并），从大到小
    static func top(_ limit: Int) -> [AppMemory] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let got = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        var groups: [String: AppMemory] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(max(got, 0))) where pid > 0 {
            var usage = rusage_info_current()
            let r = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard r == 0, usage.ri_phys_footprint > 0 else { continue }   // 无权限（root 进程）时跳过
            let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = len > 0 ? String(cString: pathBuf) : ""
            var key: String, name: String, appPath: String?
            if let range = path.range(of: ".app/") {                       // 取最外层 .app
                appPath = String(path[..<range.lowerBound]) + ".app"
                key = appPath!
                name = (appPath! as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            } else {
                name = (path as NSString).lastPathComponent               // 完整文件名（proc_name 会截断）
                if name.isEmpty {
                    var nameBuf = [CChar](repeating: 0, count: 256)
                    proc_name(pid, &nameBuf, UInt32(nameBuf.count))
                    name = String(cString: nameBuf)
                }
                key = path.isEmpty ? name : path
            }
            var g = groups[key] ?? AppMemory(name: name, path: appPath, bytes: 0, processes: 0)
            g.bytes += usage.ri_phys_footprint
            g.processes += 1
            groups[key] = g
        }
        return Array(groups.values.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    static func format(_ b: UInt64) -> String {
        let d = Double(b)
        return d >= 1_073_741_824 ? String(format: "%.2f GB", d / 1_073_741_824) : String(format: "%.0f MB", d / 1_048_576)
    }

    private static var iconCache: [String: NSImage] = [:]
    static func icon(_ path: String?) -> NSImage {
        let key = path ?? ""
        if let i = iconCache[key] { return i }
        let img = path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil)!
        iconCache[key] = img
        return img
    }
}

// MARK: - 详情页数据（每张卡片点进去看到的内容）
struct AppStat { var name: String, path: String?, value: Double, processes: Int }
struct NetInterface { var bsd: String, name: String, ipv4: String, up: Double, down: Double }
struct ProcMem { var pid: pid_t, name: String, path: String?, bytes: UInt64, user: String }
struct VolumeInfo { var name: String, path: String, used: Double, total: Double }

enum DetailKind { case system, cpu, gpu, memory, temps, storage, battery, network }

/// 进程 → 所属应用（取最外层 .app；否则用可执行文件名）
enum AppIdentity {
    private static var cache: [pid_t: (key: String, name: String, path: String?)] = [:]

    /// 缓存版：同一个进程只查一次路径；不在当前进程列表里的缓存会被清掉
    static func of(_ pid: pid_t) -> (key: String, name: String, path: String?) {
        if let c = cache[pid] { return c }
        let v = lookup(pid); cache[pid] = v; return v
    }

    static func prune(_ alive: [pid_t]) {
        let set = Set(alive)
        cache = cache.filter { set.contains($0.key) }
        procCache = procCache.filter { set.contains($0.key) }
    }

    /// 单个进程：完整可执行文件名 + 所属应用路径（图标 / 在访达中显示）
    private static var procCache: [pid_t: (name: String, path: String?)] = [:]
    static func process(_ pid: pid_t) -> (name: String, path: String?) {
        if let c = procCache[pid] { return c }
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = len > 0 ? String(cString: buf) : ""
        var name = (path as NSString).lastPathComponent
        if name.isEmpty { var nb = [CChar](repeating: 0, count: 256); proc_name(pid, &nb, UInt32(nb.count)); name = String(cString: nb) }
        if name.isEmpty { name = "pid \(pid)" }
        let v = (name, of(pid).path ?? (path.isEmpty ? nil : path))
        procCache[pid] = v; return v
    }

    private static func lookup(_ pid: pid_t) -> (key: String, name: String, path: String?) {
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = len > 0 ? String(cString: buf) : ""
        if let r = path.range(of: ".app/") {
            let app = String(path[..<r.lowerBound]) + ".app"
            return (app, (app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""), app)
        }
        var name = (path as NSString).lastPathComponent
        if name.isEmpty {
            var nb = [CChar](repeating: 0, count: 256); proc_name(pid, &nb, UInt32(nb.count)); name = String(cString: nb)
        }
        return (path.isEmpty ? name : path, name, nil)
    }

    static func group(_ perPid: [pid_t: Double], limit: Int) -> [AppStat] {
        var g: [String: AppStat] = [:]
        for (pid, v) in perPid where v > 0 {
            let id = of(pid)
            var a = g[id.key] ?? AppStat(name: id.name, path: id.path, value: 0, processes: 0)
            a.value += v; a.processes += 1
            g[id.key] = a
        }
        return Array(g.values.sorted { $0.value > $1.value }.prefix(limit))
    }

    static func allPids() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let got = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let alive = pids.prefix(Int(max(got, 0))).filter { $0 > 0 }
        prune(alive)
        return alive
    }
}

final class DetailProvider {
    var cores: [Double] = []
    var cpuApps: [AppStat] = [], gpuApps: [AppStat] = [], netApps: [AppStat] = []
    var memApps: [AppMemory] = []
    var memProcs: [ProcMem] = []
    var interfaces: [NetInterface] = []
    var volumes: [VolumeInfo] = []
    var sensors: [(String, Double)] = []
    var gpuStats: [String: Int] = [:]
    var sampled = false

    private var prevCores: [Int32]?
    private var prevCPU: [pid_t: UInt64] = [:], prevGPU: [pid_t: UInt64] = [:]
    private var prevIf: [String: (UInt64, UInt64)] = [:]
    private let timebase: Double = { var tb = mach_timebase_info(); mach_timebase_info(&tb); return Double(tb.numer) / Double(tb.denom) }()
    private lazy var ifNames: [String: String] = {
        var map: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let b = SCNetworkInterfaceGetBSDName(i) as String?, let n = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? { map[b] = n }
        }
        return map
    }()

    func reset() { stopNetwork(); sampled = false }
    func resetAll() { stopNetwork(); prevCores = nil; prevCPU = [:]; prevGPU = [:]; prevIf = [:]; sampled = false
                   cores = []; cpuApps = []; gpuApps = []; netApps = [] }

    private var tCPU: CFTimeInterval = 0, tGPU: CFTimeInterval = 0, tIf: CFTimeInterval = 0
    private func dt(_ t: inout CFTimeInterval) -> Double {
        let now = CACurrentMediaTime(); defer { t = now }
        return max(now - t, 0.001)
    }

    /// 面板打开时先记一份基准：之后点进 CPU / GPU / 网络，马上就能算出速度，不用再等一轮
    func prime() {
        refreshCores(); refreshCPUApps(dt(&tCPU)); refreshGPU(dt(&tGPU)); refreshInterfaces(dt(&tIf))
    }

    func prewarmStorage() { refreshAppSizes() }

    func refresh(_ kind: DetailKind) {
        switch kind {
        case .cpu:     refreshCores(); refreshCPUApps(dt(&tCPU))
        case .gpu:     refreshGPU(dt(&tGPU))
        case .memory:  memApps = ProcessMemory.top(PanelController.procRows); startMemTop()
        case .temps:   sensors = TempMonitor.shared.readAll()
        case .storage: refreshVolumes(); refreshAppSizes()
        case .network: refreshInterfaces(dt(&tIf)); refreshNetApps()
        default: break
        }
        sampled = true
    }

    // 每个核心占用
    private func refreshCores() {
        var n: natural_t = 0, info: processor_info_array_t?, count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) == KERN_SUCCESS, let info else { return }
        let arr = Array(UnsafeBufferPointer(start: info, count: Int(count)))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        if let p = prevCores, p.count == arr.count {
            cores = (0..<Int(n)).map { i in
                let b = i * Int(CPU_STATE_MAX)
                func d(_ k: Int32) -> Double { Double(arr[b + Int(k)] &- p[b + Int(k)]) }
                let busy = d(CPU_STATE_USER) + d(CPU_STATE_SYSTEM) + d(CPU_STATE_NICE), total = busy + d(CPU_STATE_IDLE)
                return total > 0 ? busy / total : 0
            }
        }
        prevCores = arr
    }

    // 各应用 CPU%（与活动监视器一致：多线程可超过 100%）
    private func refreshCPUApps(_ dt: Double) {
        var cur: [pid_t: UInt64] = [:], rate: [pid_t: Double] = [:]
        for pid in AppIdentity.allPids() {
            var u = rusage_info_current()
            let r = withUnsafeMutablePointer(to: &u) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) } }
            guard r == 0 else { continue }
            let t = u.ri_user_time + u.ri_system_time
            cur[pid] = t
            if let p = prevCPU[pid], t >= p { rate[pid] = Double(t - p) * timebase / (dt * 1e9) }
        }
        if !prevCPU.isEmpty { cpuApps = AppIdentity.group(rate, limit: 8) }
        prevCPU = cur
    }

    // GPU：整体利用率 + 各应用（显卡驱动 AppUsage 里的累计 GPU 时间）
    private func refreshGPU(_ dt: Double) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var cur: [pid_t: UInt64] = [:]
        var accel = IOIteratorNext(iter)
        while accel != 0 {
            if let st = IORegistryEntryCreateCFProperty(accel, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                for k in ["Device Utilization %", "Renderer Utilization %", "Tiler Utilization %", "In use system memory", "Alloc system memory"] {
                    if let v = st[k] as? Int { gpuStats[k] = v }
                }
            }
            var it: io_iterator_t = 0
            if IORegistryEntryCreateIterator(accel, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &it) == KERN_SUCCESS {
                var c = IOIteratorNext(it)
                while c != 0 {
                    if let creator = IORegistryEntryCreateCFProperty(c, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                       let usage = IORegistryEntryCreateCFProperty(c, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]],
                       let pidStr = creator.split(separator: ",").first?.split(separator: " ").last, let pid = pid_t(pidStr) {
                        let t = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
                        cur[pid, default: 0] += t
                    }
                    IOObjectRelease(c); c = IOIteratorNext(it)
                }
                IOObjectRelease(it)
            }
            IOObjectRelease(accel); accel = IOIteratorNext(iter)
        }
        var rate: [pid_t: Double] = [:]
        for (pid, t) in cur { if let p = prevGPU[pid], t >= p { rate[pid] = Double(t - p) / (dt * 1e9) } }
        if !prevGPU.isEmpty { gpuApps = AppIdentity.group(rate, limit: 8) }
        prevGPU = cur
    }

    // 网卡：名称、IPv4、实时速度
    private func refreshInterfaces(_ dt: Double) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return }
        defer { freeifaddrs(head) }
        var ips: [String: String] = [:], bytes: [String: (UInt64, UInt64)] = [:]
        var p = head
        while let ifa = p?.pointee {
            defer { p = ifa.ifa_next }
            let name = String(cString: ifa.ifa_name)
            guard name != "lo0", let addr = ifa.ifa_addr, (ifa.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                ips[name] = String(cString: host)
            } else if addr.pointee.sa_family == UInt8(AF_LINK), let d = ifa.ifa_data {
                let x = d.assumingMemoryBound(to: if_data.self).pointee
                bytes[name] = (UInt64(x.ifi_ibytes), UInt64(x.ifi_obytes))
            }
        }
        interfaces = ips.keys.sorted().prefix(3).map { n in
            let b = bytes[n] ?? (0, 0), pb = prevIf[n] ?? b
            return NetInterface(bsd: n, name: ifNames[n] ?? n, ipv4: ips[n] ?? "",
                                up: b.1 >= pb.1 ? Double(b.1 - pb.1) / dt : 0, down: b.0 >= pb.0 ? Double(b.0 - pb.0) / dt : 0)
        }
        prevIf = bytes
    }

    // 各应用网络流量：常驻 nettop（-d 差值模式，每秒输出一组“这一秒的字节数”）
    private var netProc: Process?
    private var netPipe: Pipe?            // 必须持有，否则管道被释放、读不到数据
    private var netBuffer = ""
    private var netBlock: [pid_t: Double] = [:]
    private var netBlocks = 0

    private func refreshNetApps() {
        guard netProc == nil else { return }
        let p = Process()
        // 经 script 套一个伪终端：nettop 输出到管道时会整块缓冲，要等很久才有数据；伪终端下逐行输出
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/usr/bin/nettop", "-P", "-d", "-x", "-L", "0", "-s", "1", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        netBuffer = ""; netBlock = [:]; netBlocks = 0
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            DispatchQueue.main.async { self?.consumeNet(text) }
        }
        guard (try? p.run()) != nil else { return }
        netProc = p; netPipe = pipe
    }

    private func consumeNet(_ chunk: String) {
        netBuffer += chunk
        while let nl = netBuffer.firstIndex(where: \.isNewline) {   // 伪终端输出 "\r\n"，Swift 里是一个字符
            let line = netBuffer[..<nl].trimmingCharacters(in: .whitespacesAndNewlines); netBuffer.removeSubrange(...nl)
            if line.hasPrefix(",") {                      // 新一组开始：发布上一组
                if netBlocks >= 2 {   // 第一组是累计值，跳过
                    netApps = AppIdentity.group(netBlock, limit: 8)
                    if CommandLine.arguments.contains("--open-panel") {
                        NSLog("net debug: block=%d apps=%d top=%@", netBlocks, netApps.count, netApps.first.map { "\($0.name) \(NetMonitor.format($0.value))" } ?? "-")
                    }
                }
                netBlock = [:]; netBlocks += 1
                continue
            }
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 3, let i = Double(f[1]), let o = Double(f[2]),
                  let pid = pid_t(f[0].split(separator: ".").last ?? "") else { continue }
            netBlock[pid, default: 0] += i + o
        }
    }

    func stopNetwork() {
        netPipe?.fileHandleForReading.readabilityHandler = nil
        netProc?.terminate(); netProc = nil; netPipe = nil
        netApps = []
        stopMemTop()
    }

    // 占内存最多的进程（含 root / 其他用户的系统进程）：普通 API 读不到别的用户的进程，
    // top 可以。详情页打开时常驻一个 top，每 3 秒一组（约占 4% 单核），关闭页面就结束
    private var topProc: Process?
    private var topPipe: Pipe?
    private var topBuffer = ""
    private var topBlock: [ProcMem] = []

    private func startMemTop() {
        guard topProc == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")   // 伪终端：避免 top 输出到管道时整块缓冲
        p.arguments = ["-q", "/dev/null", "/usr/bin/top", "-l", "0", "-s", "3", "-o", "mem", "-n", "\(PanelController.topProcRows)", "-stats", "pid,mem,user"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        topBuffer = ""; topBlock = []
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            DispatchQueue.main.async { self?.consumeTop(text) }
        }
        guard (try? p.run()) != nil else { return }
        topProc = p; topPipe = pipe
    }

    private func consumeTop(_ chunk: String) {
        topBuffer += chunk
        while let nl = topBuffer.firstIndex(where: \.isNewline) {
            let line = topBuffer[..<nl].trimmingCharacters(in: .whitespacesAndNewlines); topBuffer.removeSubrange(...nl)
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            if f.first == "PID" { topBlock = []; continue }               // 新一组
            guard f.count >= 3, let pid = pid_t(f[0]), let bytes = Self.topBytes(f[1]) else { continue }
            let id = AppIdentity.process(pid)
            topBlock.append(ProcMem(pid: pid, name: id.name, path: id.path, bytes: bytes, user: String(f[2])))
            if topBlock.count == PanelController.topProcRows { memProcs = topBlock; topBlock = [] }
        }
    }

    /// top 的 MEM 列："2368M"、"996M+"、"12K"、"1.2G"
    private static func topBytes(_ s: Substring) -> UInt64? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let u = t.last, let v = Double(t.dropLast()) else { return nil }
        let m: Double = u == "K" ? 1024 : u == "M" ? 1_048_576 : u == "G" ? 1_073_741_824 : u == "B" ? 1 : 0
        return m > 0 ? UInt64(v * m) : nil
    }

    private func stopMemTop() {
        topPipe?.fileHandleForReading.readabilityHandler = nil
        topProc?.terminate(); topProc = nil; topPipe = nil
        memProcs = []
    }

    // 各应用占用的磁盘空间：后台用 du 计算，缓存 10 分钟
    var appSizes: [AppStat] = []
    var sizeScanning = false
    private var sizeScanTime: CFTimeInterval = 0

    private func refreshAppSizes() {
        guard !sizeScanning, appSizes.isEmpty || CACurrentMediaTime() - sizeScanTime > 600 else { return }
        sizeScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
            let apps = dirs.flatMap { d in ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".app") }.map { d + "/" + $0 } }
            var result: [AppStat] = []
            if !apps.isEmpty {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                p.qualityOfService = .background
                p.arguments = ["-sk"] + apps
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                if (try? p.run()) != nil {
                    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    p.waitUntilExit()
                    for line in out.split(separator: "\n") {
                        let parts = line.split(separator: "\t", maxSplits: 1)
                        guard parts.count == 2, let kb = Double(parts[0]) else { continue }
                        let path = String(parts[1])
                        result.append(AppStat(name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                                              path: path, value: kb * 1024, processes: 1))
                    }
                }
            }
            result.sort { $0.value > $1.value }
            DispatchQueue.main.async {
                self?.appSizes = Array(result.prefix(12)); self?.sizeScanning = false; self?.sizeScanTime = CACurrentMediaTime()
            }
        }
    }

    private func refreshVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let free = v.volumeAvailableCapacityForImportantUsage.map(Double.init) ?? Double(v.volumeAvailableCapacity ?? 0)
            return VolumeInfo(name: v.volumeName ?? u.lastPathComponent, path: u.path, used: Double(total) - free, total: Double(total))
        }.prefix(5).map { $0 }
    }
}

// MARK: - 电池详细信息
enum BatteryDetail {
    static func rows() -> [(String, String)] {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard svc != 0 else { return [(L("电池", "Battery"), L("无电池", "No battery"))] }
        defer { IOObjectRelease(svc) }
        func num(_ k: String) -> NSNumber? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber }
        let data = IORegistryEntryCreateCFProperty(svc, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] ?? [:]
        func int(_ k: String) -> Int? { num(k)?.intValue ?? (data[k] as? NSNumber)?.intValue }
        let adapter = IORegistryEntryCreateCFProperty(svc, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]

        var r: [(String, String)] = []
        if let b = SystemInfo.battery() {
            r.append((L("电量", "Charge"), "\(b.percent)%"))
            r.append((L("状态", "Status"), SystemInfo.stateText(b.state)))
        }
        if let h = SystemInfo.batteryHealth() {
            r.append((L("健康度", "Health"), Draw.pct(h.health)))
            r.append((L("循环次数", "Cycle Count"), "\(h.cycles) / \(h.designCycles)"))
        }
        if let d = int("DesignCapacity") { r.append((L("设计容量", "Design Capacity"), "\(d) mAh")) }
        if let f = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") { r.append((L("满充容量", "Full Charge Capacity"), "\(f) mAh")) }
        if let c = int("AppleRawCurrentCapacity") { r.append((L("当前容量", "Current Capacity"), "\(c) mAh")) }
        let mv = Double(int("Voltage") ?? 0)
        let ma = Double(Int32(truncatingIfNeeded: num("InstantAmperage")?.int64Value ?? num("Amperage")?.int64Value ?? 0))
        if mv > 0 { r.append((L("电压", "Voltage"), String(format: "%.2f V", mv / 1000))) }
        r.append((L("电流", "Current"), String(format: "%.0f mA", ma)))
        r.append((L("功率", "Power"), String(format: "%.1f W", mv * ma / 1_000_000)))
        if let t = TempMonitor.shared.read().battery { r.append((L("温度", "Temperature"), TempUnit.format(t))) }
        if let a = adapter, let w = a["Watts"] as? Int { r.append((L("电源适配器", "Power Adapter"), "\(w) W")) }
        if let t = SystemInfo.batteryTime() { r.insert((t.label, t.value), at: min(2, r.count)) }
        return r
    }
}

// MARK: - 本机详细信息
enum SystemDetail {
    static func rows(_ spec: MachineSpec) -> [(String, String)] {
        let up = Int(ProcessInfo.processInfo.systemUptime)
        let uptime = up >= 86400 ? L("\(up / 86400) 天 \(up % 86400 / 3600) 小时", "\(up / 86400)d \(up % 86400 / 3600)h")
                                 : L("\(up / 3600) 小时 \(up % 3600 / 60) 分", "\(up / 3600)h \(up % 3600 / 60)m")
        let screens = NSScreen.screens.map { s -> String in
            let px = s.frame.size.applying(.init(scaleX: s.backingScaleFactor, y: s.backingScaleFactor))
            return "\(s.localizedName) \(Int(px.width))×\(Int(px.height))"
        }
        var r: [(String, String)] = [
            (L("机型", "Model"), spec.model),
            (L("型号标识", "Model Identifier"), MachineSpec.sysctlString("hw.model")),
            (L("芯片", "Chip"), spec.chip),
            ("CPU", spec.eCores > 0 ? L("\(spec.pCores + spec.eCores) 核（\(spec.pCores) 性能 + \(spec.eCores) 能效）", "\(spec.pCores + spec.eCores) cores (\(spec.pCores)P + \(spec.eCores)E)") : "\(spec.pCores)"),
            ("GPU", spec.gpuCores > 0 ? L("\(spec.gpuCores) 核", "\(spec.gpuCores) cores") : "--"),
            (L("内存", "Memory"), "\(spec.memoryGB) GB"),
            (L("硬盘", "Disk"), spec.diskText),
            (L("系统", "macOS"), "\(spec.os) (\(MachineSpec.sysctlString("kern.osversion")))"),
            (L("已运行", "Uptime"), uptime),
            (L("主机名", "Computer Name"), Host.current().localizedName ?? "--"),
        ]
        for (i, s) in screens.prefix(2).enumerated() { r.append((i == 0 ? L("显示器", "Displays") : "", s)) }
        return r
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
extension NSColor {
    /// 玻璃上的次要文字：比系统 secondaryLabelColor 更实，保证对比度
    static var glassSecondary: NSColor { NSColor.labelColor.withAlphaComponent(0.72) }
    static var glassTertiary: NSColor { NSColor.labelColor.withAlphaComponent(0.5) }
}

enum Draw {
    static func text(_ s: String, _ p: NSPoint, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor, right: Bool = false, mono: Bool = false, maxWidth: CGFloat? = nil) {
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        if let mw = maxWidth, str.size().width > mw {   // 太长：末尾省略号
            let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
                .draw(with: NSRect(x: p.x, y: p.y, width: mw, height: str.size().height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return
        }
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
    static func title(_ icon: String, _ name: String, in w: CGFloat, tint: NSColor = .labelColor, chevron: Bool = true) {
        let iw = symbol(icon, NSPoint(x: 14, y: 12), size: 13, color: tint)
        let x = 14 + max(iw, 14) + 6
        text(name, NSPoint(x: x, y: 12), size: 12, weight: .semibold)
        if chevron {   // 可点击提示
            let tw = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
            symbol("chevron.right", NSPoint(x: x + tw + 4, y: 12), size: 9, color: .glassTertiary)
        }
    }

    static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func level(_ f: Double) -> NSColor { f < 0.7 ? .systemGreen : (f < 0.9 ? .systemYellow : .systemRed) }
    static func tempColor(_ c: Double) -> NSColor { c < 60 ? .systemGreen : (c < 80 ? .systemYellow : .systemRed) }

    static func bar(_ r: NSRect, _ f: Double, _ color: NSColor) {
        let rad = r.height / 2
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad).fill()
        guard f > 0.005 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: max(r.height, r.width * CGFloat(min(f, 1))), height: r.height),
                     xRadius: rad, yRadius: rad).fill()
    }

    /// 平滑滚动的面积图：最新点从右侧滑入；values 为 0~1
    static func area(_ r: NSRect, _ values: [Double], scroll: Double, color: NSColor, line: Bool = false, dot: Bool = false) {
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
        if dot {   // “现在”的位置：曲线与右边缘相交处，随滚动平滑移动
            let a = pt(values.count - 2), b = pt(values.count - 1)
            let y = a.y + (b.y - a.y) * CGFloat(scroll)
            let c = NSPoint(x: r.maxX - 1, y: min(max(y, r.minY + 3), r.maxY - 3))
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)).fill()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2)).fill()
        }
    }

    static func chartBackground(_ r: NSRect, grid: Bool = true) {
        NSColor.labelColor.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        guard grid else { return }
        // 25% / 50% / 75% 参考线（虚线）
        NSColor.labelColor.withAlphaComponent(0.08).setStroke()
        for f in [0.25, 0.5, 0.75] {
            let y = r.maxY - r.height * CGFloat(f)
            let line = NSBezierPath()
            line.lineWidth = 0.5
            line.setLineDash([2, 3], count: 2, phase: 0)
            line.move(to: NSPoint(x: r.minX + 6, y: y)); line.line(to: NSPoint(x: r.maxX - 6, y: y))
            line.stroke()
        }
    }
}

// MARK: - 卡片：一块液态玻璃 + 自绘内容
final class CardView: NSView {
    var continuous = false                 // 带滚动曲线的卡片：每帧都要重画
    /// 列表卡片：根据鼠标位置返回所在行的应用路径（nil = 不在可点的行上）
    var rowAt: ((NSPoint) -> String?)?
    private(set) var hoverPoint: NSPoint?
    static var drawingHover: NSPoint?      // 绘制时当前卡片的鼠标位置，供列表画高亮
    var drawer: (CGFloat) -> Void = { _ in }
    var onClick: (() -> Void)?
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }
    override func mouseDown(with event: NSEvent) { if onClick != nil { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(p)
        pressed = false
        if inside, let path = rowAt?(p) {        // 点击列表里的应用：在访达中显示
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        if inside { onClick?() }
    }
    override func mouseMoved(with event: NSEvent) {
        guard rowAt != nil else { return }
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        if let p = hoverPoint, rowAt?(p) != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
    override func mouseEntered(with event: NSEvent) { hovered = onClick != nil }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false; hoverPoint = nil; if rowAt != nil { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func resetCursorRects() { if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    static var drawCount = 0
    override func draw(_ dirtyRect: NSRect) {
        CardView.drawCount += 1
        if hovered || pressed {   // 悬停微亮，按下更亮
            NSColor.labelColor.withAlphaComponent(pressed ? 0.12 : 0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        }
        CardView.drawingHover = rowAt != nil ? hoverPoint : nil
        drawer(bounds.width)
        CardView.drawingHover = nil
    }
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
        if CommandLine.arguments.contains("--light") { popover.appearance = NSAppearance(named: .aqua) }
        popover.animates = true
        popover.delegate = self
        build()
    }

    private struct Page { let view: NSView; let size: NSSize; let cards: [CardView] }
    private var mainPage: Page!

    /// 通用页面：rows = [(高度, [(x, 宽, 绘制, 点击)])]；底层玻璃、上层内容
    private func makePage(_ rows: [(CGFloat, [(CGFloat, CGFloat, (CGFloat) -> Void, (() -> Void)?)])], continuous: Set<Int> = [],
                          button: ((CardView, CGFloat) -> Void)? = nil) -> Page {
        let W = Self.width, g = Self.gap, M = Self.margin
        var layout: [(CGFloat, CGFloat, CGFloat, CGFloat, (CGFloat) -> Void, (() -> Void)?)] = []
        var y: CGFloat = 0
        for (h, items) in rows {
            for (x, w, d, c) in items { layout.append((x, y, w, h, d, c)) }
            y += h + g
        }
        let H = y - g
        let size = NSSize(width: W + M * 2, height: H + M * 2)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let container = NSGlassEffectContainerView(frame: root.bounds)
        container.spacing = g
        let glassHolder = NSView(frame: root.bounds)
        let contentLayer = NSView(frame: root.bounds)
        var cards: [CardView] = []
        for (i, (x, top, w, h, d, click)) in layout.enumerated() {
            let frame = NSRect(x: M + x, y: M + H - top - h, width: w, height: h)
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = 18
            glass.style = .regular
            glassHolder.addSubview(glass)
            let card = CardView(frame: frame)
            card.drawer = d
            card.onClick = click
            card.continuous = continuous.contains(i)
            contentLayer.addSubview(card)
            cards.append(card)
            if i == 0 { button?(card, w) }       // 第一张卡片（标题栏）里的按钮
        }
        container.contentView = glassHolder
        root.addSubview(container)
        root.addSubview(contentLayer)
        return Page(view: root, size: size, cards: cards)
    }

    private func build() {
        let W = Self.width, g = Self.gap, half = (W - g) / 2
        mainPage = makePage([
            (56,  [(0, W, drawHeader, { [weak self] in self?.showDetail(.system) })]),
            (134, [(0, W, drawCPU, { [weak self] in self?.showDetail(.cpu) })]),
            (118, [(0, half, drawGPU, { [weak self] in self?.showDetail(.gpu) }), (half + g, half, drawTemps, { [weak self] in self?.showDetail(.temps) })]),
            (84,  [(0, W, drawMemory, { [weak self] in self?.showDetail(.memory) })]),
            (138, [(0, half, drawStorage, { [weak self] in self?.showDetail(.storage) }), (half + g, half, drawBattery, { [weak self] in self?.showDetail(.battery) })]),
            (96,  [(0, W, drawNetwork, { [weak self] in self?.showDetail(.network) })]),
        ], continuous: [1, 2, 7],    // CPU、GPU、网络三张带曲线的卡片（卡片按出现顺序编号）
           button: { [weak self] card, w in
            guard let self else { return }
            let b = NSButton(image: NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")!,
                             target: self, action: #selector(self.settingsClicked(_:)))
            b.isBordered = false
            b.contentTintColor = .labelColor
            b.frame = NSRect(x: w - 38, y: 16, width: 24, height: 24)
            card.addSubview(b)
        })
        cards = mainPage.cards
        // host 容纳当前页面；页面贴顶（高度变化时随 popover 平滑伸缩）
        host = NSView(frame: NSRect(origin: .zero, size: mainPage.size))
        mainPage.view.autoresizingMask = [.minYMargin]
        host.addSubview(mainPage.view)
        current = mainPage.view
        let vc = NSViewController()
        vc.view = host
        popover.contentViewController = vc
        popover.contentSize = mainPage.size
    }

    // MARK: 详情页（每张卡片都能点进去）
    static let procRows = 8, topProcRows = 10
    let detail = DetailProvider()
    private var detailKind: DetailKind = .memory
    private var detailPages: [String: Page] = [:]
    private var detailTimer: Timer?
    private var kvRows: [(String, String)] = []

    func debugShow(_ k: DetailKind) { showDetail(k) }

    // MARK: 设置页：和详情页一样从右边滑入
    var settingsModel: SettingsModel?
    private var settingsPage: Page?

    func showSettings() {
        guard let m = settingsModel else { return }
        let page = settingsPage ?? {
            let W = Self.width, M = Self.margin, g = Self.gap
            let header = makePage([(56, [(0, W, { [weak self] w in self?.drawSettingsHeader(w) }, nil)])], button: { [weak self] card, _ in
                guard let self else { return }
                let b = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                                 target: self, action: #selector(self.backToMain))
                b.isBordered = false
                b.contentTintColor = .labelColor
                b.frame = NSRect(x: 10, y: 16, width: 24, height: 24)
                card.addSubview(b)
            })
            let formH: CGFloat = 600
            let size = NSSize(width: header.size.width, height: header.size.height + g + formH)
            let root = NSView(frame: NSRect(origin: .zero, size: size))
            header.view.setFrameOrigin(NSPoint(x: 0, y: size.height - header.size.height))
            root.addSubview(header.view)
            let host = NSHostingView(rootView: SettingsView(m: m, width: W + M * 2 - 8, height: formH))
            host.frame = NSRect(x: 4, y: 0, width: W + M * 2 - 8, height: formH)
            root.addSubview(host)
            let p = Page(view: root, size: size, cards: header.cards)
            settingsPage = p
            return p
        }()
        switchTo(page)
    }

    private func drawSettingsHeader(_ w: CGFloat) {
        Draw.symbol("gearshape.fill", NSPoint(x: 40, y: 10), size: 15, color: .glassSecondary)
        Draw.text(L("设置", "Settings"), NSPoint(x: 64, y: 8), size: 13, weight: .semibold)
        Draw.text("MenuRunner " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
                  NSPoint(x: 64, y: 29), size: 10, color: .glassSecondary)
    }
    var debugMainView: NSView { mainPage.view }
    var debugCardFrames: [NSRect] { mainPage.cards.map { $0.frame } }

    private func key(_ k: DetailKind) -> String { "\(k)" }

    private func showDetail(_ k: DetailKind) {
        detailKind = k
        detail.reset()
        refreshDetail()
        let W = Self.width
        let dynamic = k == .storage || k == .temps || k == .system || k == .battery || k == .network   // 高度随数据条数变化，不缓存
        let page = (dynamic ? nil : detailPages[key(k)]) ?? {
            let header: (CGFloat, [(CGFloat, CGFloat, (CGFloat) -> Void, (() -> Void)?)]) = (56, [(0, W, drawDetailHeader, nil)])
            var rows = [header]
            switch k {
            case .system, .battery: rows.append((CGFloat(max(1, kvRows.count)) * 24 + 14, [(0, W, drawKV, nil)]))
            case .cpu:     rows += [(132, [(0, W, drawCores, nil)]), (8 * 30 + 46, [(0, W, { [weak self] w in self?.drawApps(w, L("占用 CPU 最多的应用", "Top apps by CPU"), self?.detail.cpuApps ?? [], { String(format: "%.1f%%", $0 * 100) }) }, nil)])]
            case .gpu:     rows += [(4 * 24 + 46, [(0, W, drawGPUStats, nil)]), (8 * 30 + 46, [(0, W, { [weak self] w in self?.drawApps(w, L("占用 GPU 最多的应用", "Top apps by GPU"), self?.detail.gpuApps ?? [], { String(format: "%.1f%%", $0 * 100) }) }, nil)])]
            case .memory:  rows += [(CGFloat(Self.procRows) * 30 + 46, [(0, W, drawProcessList, nil)]),
                                    (CGFloat(Self.topProcRows) * 30 + 46, [(0, W, drawTopProcs, nil)])]
            case .temps:   rows.append((CGFloat(max(1, min(14, (detail.sensors.count + 1) / 2))) * 22 + 24, [(0, W, drawSensors, nil)]))
            case .storage: rows += [(CGFloat(max(1, detail.volumes.count)) * 46 + 14, [(0, W, drawVolumes, nil)]),
                                    (12 * 30 + 46, [(0, W, drawAppSizes, nil)])]
            case .network: rows += [(CGFloat(max(1, detail.interfaces.count)) * 40 + 40, [(0, W, drawInterfaces, nil)]), (8 * 30 + 46, [(0, W, { [weak self] w in self?.drawApps(w, L("网络流量最大的应用", "Top apps by network"), self?.detail.netApps ?? [], { NetMonitor.format($0) }) }, nil)])]
            }
            let p = makePage(rows, button: { [weak self] card, _ in
                guard let self else { return }
                let b = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!,
                                 target: self, action: #selector(self.backToMain))
                b.isBordered = false
                b.contentTintColor = .labelColor
                b.frame = NSRect(x: 10, y: 16, width: 24, height: 24)
                card.addSubview(b)
            })
            // 列表卡片（最后一张）：悬停高亮、点击在访达中显示
            if let list = p.cards.last {
                switch k {
                case .memory:
                    list.rowAt = { [weak self] pt in self.flatMap { $0.rowHit(pt, top: 36, paths: $0.detail.memProcs.map { $0.path }) } }
                    p.cards[p.cards.count - 2].rowAt = { [weak self] pt in self.flatMap { $0.rowHit(pt, top: 36, paths: $0.detail.memApps.map { $0.path }) } }
                case .cpu, .gpu, .network, .storage:
                    list.rowAt = { [weak self] pt in
                        guard let self else { return nil }
                        let apps = k == .cpu ? self.detail.cpuApps : k == .gpu ? self.detail.gpuApps : k == .network ? self.detail.netApps : self.detail.appSizes
                        return self.rowHit(pt, top: 36, paths: apps.map { $0.path })
                    }
                default: break
                }
            }
            detailPages[key(k)] = p
            return p
        }()
        switchTo(page)
        detailTimer?.invalidate()
        let interval: Double = (k == .memory || k == .storage || k == .system) ? 2 : 1.5
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refreshDetail() }
        RunLoop.main.add(t, forMode: .common)
        detailTimer = t
    }

    private func refreshDetail() {
        detail.refresh(detailKind)
        settle()
        switch detailKind {
        case .system:  kvRows = SystemDetail.rows(spec)
        case .battery: kvRows = BatteryDetail.rows()
        default: break
        }
    }

    @objc private func backToMain() {
        detailTimer?.invalidate(); detailTimer = nil
        detail.stopNetwork()
        switchTo(mainPage, forward: false, animated: popover.isShown)
    }

    private var detailTitle: (icon: String, tint: NSColor, title: String, value: String, sub: String) {
        let m = model
        switch detailKind {
        case .system:  return ("laptopcomputer", .labelColor, spec.model, "", spec.summary)
        case .cpu:     return ("cpu", .systemBlue, "CPU", Draw.pct(m.v("cpu")), spec.detail.components(separatedBy: " · ").first ?? "")
        case .gpu:     return ("cpu.fill", .systemGreen, "GPU", m.gpu == nil ? "--" : Draw.pct(m.v("gpu")), spec.gpuCores > 0 ? L("\(spec.gpuCores) 核 GPU", "\(spec.gpuCores)-core GPU") : "")
        case .memory:  return ("memorychip", .systemPurple, L("内存占用", "Memory Usage"), "\(SystemInfo.gb(m.memory.used)) / \(SystemInfo.gb(m.memory.total))", L("应用 · 进程", "Apps · processes"))
        case .temps:   return ("thermometer.medium", .systemOrange, L("温度传感器", "Temperature Sensors"), m.temps.soc.map { TempUnit.format($0) } ?? "--", L("\(detail.sensors.count) 个传感器", "\(detail.sensors.count) sensors"))
        case .storage: return ("internaldrive", .systemIndigo, L("存储", "Storage"), m.storage.map { Draw.pct($0.used / $0.total) } ?? "--", L("已挂载的卷", "Mounted volumes"))
        case .battery: return ("battery.100", .systemGreen, L("电池", "Battery"), m.battery.map { "\($0.percent)%" } ?? "--", m.battery.map { SystemInfo.stateText($0.state) } ?? "")
        case .network: return ("network", .systemTeal, L("网络", "Network"), "↓ " + NetMonitor.format(m.v("down")), "↑ " + NetMonitor.format(m.v("up")))
        }
    }

    private func drawDetailHeader(_ w: CGFloat) {
        let h = detailTitle
        Draw.symbol(h.icon, NSPoint(x: 40, y: 10), size: 15, color: h.tint)
        Draw.text(h.title, NSPoint(x: 64, y: 8), size: 13, weight: .semibold)
        Draw.text(h.sub, NSPoint(x: 64, y: 29), size: 10, color: .glassSecondary)
        Draw.text(h.value, NSPoint(x: w - 14, y: 12), size: 15, weight: .semibold, right: true, mono: true)
    }

    /// 鼠标悬停在这一行上时画高亮，并在右侧提示可在访达中显示
    private func rowHighlight(_ y: CGFloat, _ w: CGFloat, clickable: Bool) {
        guard clickable, let h = CardView.drawingHover, h.y >= y - 4, h.y < y + 26 else { return }
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: y - 4, width: w - 16, height: 30), xRadius: 8, yRadius: 8).fill()
    }

    /// 列表行命中：top = 第一行的 y，返回该行应用的路径
    private func rowHit(_ p: NSPoint, top: CGFloat, paths: [String?]) -> String? {
        guard p.y >= top - 4 else { return nil }
        let i = Int((p.y - top + 4) / 30)
        return i < paths.count ? paths[i] : nil
    }

    private func sectionTitle(_ s: String) { Draw.text(s, NSPoint(x: 14, y: 12), size: 11, weight: .semibold, color: .glassSecondary) }

    private func drawKV(_ w: CGFloat) {
        var y: CGFloat = 12
        for (k, v) in kvRows {
            Draw.text(k, NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
            Draw.text(v, NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true)
            y += 24
        }
    }

    private func drawCores(_ w: CGFloat) {
        sectionTitle(L("每个核心", "Per core"))
        let cores = detail.cores
        guard !cores.isEmpty else { Draw.text(L("采样中…", "Sampling…"), NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return }
        let e = spec.eCores, n = cores.count
        let gap: CGFloat = 6, bw = (w - 28 - gap * CGFloat(n - 1)) / CGFloat(n)
        let top: CGFloat = 36, h: CGFloat = 64
        for (i, v) in cores.enumerated() {
            let x = 14 + CGFloat(i) * (bw + gap)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: top, width: bw, height: h), xRadius: 4, yRadius: 4).fill()
            let isE = i < e
            (isE ? NSColor.systemTeal : NSColor.systemBlue).setFill()
            let fh = max(3, h * CGFloat(min(v, 1)))
            NSBezierPath(roundedRect: NSRect(x: x, y: top + h - fh, width: bw, height: fh), xRadius: 4, yRadius: 4).fill()
            let label = isE ? "E\(i + 1)" : "P\(i - e + 1)"
            let ls = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.glassSecondary])
            ls.draw(at: NSPoint(x: x + (bw - ls.size().width) / 2, y: top + h + 4))
            let vs = NSAttributedString(string: "\(Int(v * 100))", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular), .foregroundColor: NSColor.glassTertiary])
            vs.draw(at: NSPoint(x: x + (bw - vs.size().width) / 2, y: top + h + 16))
        }
    }

    private func drawApps(_ w: CGFloat, _ title: String, _ apps: [AppStat], _ fmt: (Double) -> String) {
        sectionTitle(title)
        guard !apps.isEmpty else {
            let hint = detailKind == .network ? L("采样中…（约 2 秒）", "Sampling… (about 2 s)") : L("采样中…", "Sampling…")
            Draw.text(hint, NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return
        }
        let maxV = max(apps.first?.value ?? 1, 0.0001)
        var y: CGFloat = 36
        for a in apps {
            rowHighlight(y, w, clickable: a.path != nil)
            ProcessMemory.icon(a.path).draw(in: NSRect(x: 14, y: y, width: 20, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Draw.text(a.processes > 1 ? "\(a.name)  ×\(a.processes)" : a.name, NSPoint(x: 42, y: y + 1), size: 12, weight: .medium)
            Draw.text(fmt(a.value), NSPoint(x: w - 14, y: y + 1), size: 12, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 42, y: y + 20, width: w - 56, height: 3), a.value / maxV, .systemBlue)
            y += 30
        }
    }

    private func drawGPUStats(_ w: CGFloat) {
        sectionTitle(L("利用率", "Utilization"))
        var y: CGFloat = 36
        for (k, label) in [("Device Utilization %", L("设备", "Device")), ("Renderer Utilization %", L("渲染器", "Renderer")), ("Tiler Utilization %", "Tiler")] {
            let v = Double(detail.gpuStats[k] ?? 0) / 100
            Draw.text(label, NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
            Draw.text(Draw.pct(v), NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 90, y: y + 6, width: w - 150, height: 5), v, .systemGreen)
            y += 24
        }
        let mem = Double(detail.gpuStats["In use system memory"] ?? 0)
        Draw.text(L("显存（共享内存）", "GPU memory (shared)"), NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
        Draw.text(SystemInfo.gb(mem), NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
    }

    private func drawSensors(_ w: CGFloat) {
        let s = detail.sensors
        guard !s.isEmpty else { Draw.text(L("读取不到温度传感器", "No temperature sensors available"), NSPoint(x: 14, y: 14), size: 11, color: .glassTertiary); return }
        let colW = (w - 28 - 16) / 2, perCol = 14
        for (i, (name, v)) in s.prefix(perCol * 2).enumerated() {
            let x = 14 + CGFloat(i / perCol) * (colW + 16), y = 12 + CGFloat(i % perCol) * 22
            Draw.text(name, NSPoint(x: x, y: y), size: 10, color: .glassSecondary)
            Draw.text(TempUnit.format(v), NSPoint(x: x + colW, y: y), size: 10, weight: .medium, color: Draw.tempColor(v), right: true, mono: true)
        }
    }

    private func drawAppSizes(_ w: CGFloat) {
        let apps = detail.appSizes
        if apps.isEmpty {
            sectionTitle(L("应用占用空间", "Space used by apps"))
            Draw.text(detail.sizeScanning ? L("正在计算应用大小…", "Calculating app sizes…") : "", NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary)
            return
        }
        // drawApps 会画标题；“×1” 不显示
        drawApps(w, L("应用占用空间（从大到小）", "Space used by apps (largest first)"), apps, { ProcessMemory.format(UInt64($0)) })
    }

    private func drawVolumes(_ w: CGFloat) {
        var y: CGFloat = 12
        for v in detail.volumes {
            ProcessMemory.icon(v.path).draw(in: NSRect(x: 14, y: y, width: 24, height: 24), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Draw.text(v.name, NSPoint(x: 46, y: y), size: 12, weight: .medium)
            Draw.text("\(SystemInfo.gb(v.used)) / \(SystemInfo.gb(v.total))", NSPoint(x: w - 14, y: y), size: 11, color: .glassSecondary, right: true, mono: true)
            let f = v.used / v.total
            Draw.bar(NSRect(x: 46, y: y + 22, width: w - 60, height: 5), f, Draw.level(f))
            y += 46
        }
    }

    private func drawInterfaces(_ w: CGFloat) {
        sectionTitle(L("网络接口", "Interfaces"))
        guard !detail.interfaces.isEmpty else { Draw.text(L("未连接", "Not connected"), NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return }
        var y: CGFloat = 36
        for i in detail.interfaces {
            Draw.text("\(i.name)  (\(i.bsd))", NSPoint(x: 14, y: y), size: 12, weight: .medium)
            Draw.text(i.ipv4, NSPoint(x: w - 14, y: y), size: 11, color: .glassSecondary, right: true, mono: true)
            Draw.text("↑ " + NetMonitor.format(i.up), NSPoint(x: 14, y: y + 17), size: 10, color: .systemPink, mono: true)
            Draw.text("↓ " + NetMonitor.format(i.down), NSPoint(x: 120, y: y + 17), size: 10, color: .systemTeal, mono: true)
            y += 40
        }
    }

    private var host: NSView!
    private var current: NSView?

    /// 切换页面：新页从一侧滑入并淡入，旧页向另一侧滑出并淡出；popover 高度同步平滑变化
    private func switchTo(_ page: Page, forward: Bool = true, animated: Bool = true) {
        cards = page.cards
        settle()
        guard let old = current, old !== page.view else { return }
        let dx: CGFloat = 36
        // popover 不会自动改 host 的尺寸：手动设为新页面大小，新旧页面都按顶部对齐
        host.setFrameSize(page.size)
        old.setFrameOrigin(NSPoint(x: 0, y: page.size.height - old.frame.height))
        page.view.setFrameOrigin(NSPoint(x: animated ? (forward ? dx : -dx) : 0, y: 0))
        page.view.alphaValue = animated ? 0 : 1
        host.addSubview(page.view)
        current = page.view
        popover.contentSize = page.size
        let finish = {
            old.removeFromSuperview(); old.alphaValue = 1; old.setFrameOrigin(.zero)
            page.view.window?.invalidateCursorRects(for: page.view)
        }
        guard animated, !CommandLine.arguments.contains("--no-anim") else { finish(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)   // 快出慢收
            ctx.allowsImplicitAnimation = true
            page.view.animator().alphaValue = 1
            page.view.animator().setFrameOrigin(NSPoint(x: 0, y: page.view.frame.minY))
            old.animator().alphaValue = 0
            old.animator().setFrameOrigin(NSPoint(x: forward ? -dx : dx, y: old.frame.minY))
        }, completionHandler: finish)
    }

    private func drawProcessList(_ w: CGFloat) {
        let total = Double(model.memory.total)
        let procs = detail.memApps
        let maxBytes = Double(procs.first?.bytes ?? 1)
        sectionTitle(L("按应用汇总", "By app"))
        var y: CGFloat = 36
        for p in procs {
            rowHighlight(y, w, clickable: p.path != nil)
            ProcessMemory.icon(p.path).draw(in: NSRect(x: 14, y: y, width: 20, height: 20), from: .zero, operation: .sourceOver,
                                            fraction: 1, respectFlipped: true, hints: nil)
            let name = p.processes > 1 ? "\(p.name)  ×\(p.processes)" : p.name
            Draw.text(name, NSPoint(x: 42, y: y + 1), size: 12, weight: .medium)
            Draw.text(ProcessMemory.format(p.bytes), NSPoint(x: w - 14, y: y + 1), size: 12, weight: .medium, right: true, mono: true)
            let f = Double(p.bytes) / maxBytes
            Draw.bar(NSRect(x: 42, y: y + 20, width: w - 56, height: 3), f,
                     Double(p.bytes) / total > 0.15 ? .systemOrange : .systemPurple)
            y += 30
        }
    }

    /// 单个进程排行（含系统进程），非当前用户的进程在名字后标出所属用户
    private func drawTopProcs(_ w: CGFloat) {
        sectionTitle(L("占内存最多的进程（含系统进程）", "Top processes (incl. system)"))
        let procs = detail.memProcs, total = Double(model.memory.total)
        guard !procs.isEmpty else { Draw.text(L("采样中…", "Sampling…"), NSPoint(x: 14, y: 40), size: 11, color: .glassTertiary); return }
        let maxBytes = Double(max(procs.first?.bytes ?? 1, 1)), me = NSUserName()
        var y: CGFloat = 36
        for p in procs {
            rowHighlight(y, w, clickable: p.path != nil)
            ProcessMemory.icon(p.path).draw(in: NSRect(x: 14, y: y, width: 20, height: 20), from: .zero, operation: .sourceOver,
                                            fraction: 1, respectFlipped: true, hints: nil)
            let value = ProcessMemory.format(p.bytes)
            var nameW = w - 56 - 70
            if p.user != me {
                let tag = p.user.hasPrefix("_") ? String(p.user.dropFirst()) : p.user
                Draw.text(tag, NSPoint(x: w - 14 - 78, y: y + 3), size: 9, color: .glassTertiary, right: true)
                nameW -= 70
            }
            Draw.text(p.name, NSPoint(x: 42, y: y + 1), size: 12, weight: .medium, maxWidth: nameW)
            Draw.text(value, NSPoint(x: w - 14, y: y + 1), size: 12, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 42, y: y + 20, width: w - 56, height: 3), Double(p.bytes) / maxBytes,
                     Double(p.bytes) / total > 0.15 ? .systemOrange : .systemPurple)
            y += 30
        }
    }

    @objc private func settingsClicked(_ sender: NSButton) { onSettings(sender) }

    var isVisible: Bool { popover.isShown }
    var onMainPage: Bool { cards.first === mainPage.cards.first }

    /// 主页打开时随采样更新“最忙应用”和内存压力
    func sampleMain() {
        settle()
        memoryPressure = SystemInfo.memoryPressure()
        if isVisible && onMainPage { detail.refresh(.cpu) }
    }

    func show(below button: NSStatusBarButton) {
        model.resetShown()                      // 数字从 0 滚动、条形从空长满
        detail.prime()
        settle(); settleUntil += 0.6                    // 打开时从 0 长出来，多给一点时间
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startTimer()
        // 点其他地方就收起：菜单栏小工具不是激活应用，popover 的 .transient 收不到“失去焦点”，
        // 所以自己监听别的应用里的鼠标按下（全局监听不会收到本应用面板里的点击）
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.hide()
            }
        }
        onVisibilityChange(true)
    }

    func hide() { popover.performClose(nil) }

    private var outsideMonitor: Any?

    func popoverDidClose(_ notification: Notification) {
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        timer?.invalidate(); timer = nil
        if cards.first !== mainPage.cards.first { backToMain() }
        onVisibilityChange(false)
    }

    private func startTimer() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.frame() }   // 30fps 足够平滑
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var frameCount = 0
    private var settleUntil: CFTimeInterval = 0
    /// 数据更新 / 页面切换后调用：接下来 0.8 秒内重画所有卡片，让数字和条形平滑过渡
    func settle() { settleUntil = CACurrentMediaTime() + 0.8 }
    private func frame() {
        frameCount += 1
        if CommandLine.arguments.contains("--open-panel"), frameCount % 60 == 0 {
            NSLog("panel debug: frames=%d cards=%d host=%@ content=%@ win=%@ subviews=%d", frameCount, cards.count,
                  NSStringFromSize(host.frame.size), NSStringFromSize(popover.contentSize),
                  NSStringFromSize(host.window?.frame.size ?? .zero), host.subviews.count)
        }
        let now = CACurrentMediaTime()
        model.tick(dt: now - lastTick); lastTick = now
        // 只重画需要动的：曲线卡片每帧；其他卡片只在数值缓动期间（打开 / 每次采样后 0.8 秒）
        let settling = now < settleUntil
        for c in cards where c.continuous || settling { c.needsDisplay = true }
        if onMainPage, model.battery?.state == "charging", mainPage.cards.count > 6 { mainPage.cards[6].needsDisplay = true }   // 充电动画
    }

    func redrawAll() { cards.forEach { $0.needsDisplay = true; $0.displayIfNeeded() } }

    // MARK: 各卡片绘制
    var spec = MachineSpec.basic()

    private func drawHeader(_ w: CGFloat) {
        let icon = spec.model.contains("Book") ? "laptopcomputer" : (spec.model.contains("iMac") ? "desktopcomputer" : "macmini")
        Draw.symbol(icon, NSPoint(x: 14, y: 10), size: 15, color: .labelColor)
        Draw.text(spec.model, NSPoint(x: 42, y: 8), size: 13, weight: .semibold)
        let mw = NSAttributedString(string: spec.model, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width
        Draw.text(spec.summary, NSPoint(x: 42 + mw + 8, y: 9), size: 12, weight: .medium, color: .glassSecondary)
        Draw.text(spec.detail, NSPoint(x: 42, y: 29), size: 10, color: .glassSecondary)
    }

    private func drawCPU(_ w: CGFloat) {
        let m = model
        Draw.title("cpu", "CPU", in: w, tint: .systemBlue)
        Draw.text(Draw.pct(m.v("cpu")), NSPoint(x: w - 14, y: 6), size: 24, weight: .semibold, right: true, mono: true)
        if let top = detail.cpuApps.first, onMainPage {   // 最忙的应用
            ProcessMemory.icon(top.path).draw(in: NSRect(x: 14, y: 29, width: 12, height: 12), from: .zero, operation: .sourceOver,
                                              fraction: 1, respectFlipped: true, hints: nil)
            let cores = Double(max(spec.pCores + spec.eCores, 1))   // 换算成占整机 CPU 的比例，与上面的总数一致
            Draw.text(L("最忙：", "Busiest: ") + top.name + String(format: "  %.0f%%", top.value / cores * 100),
                      NSPoint(x: 30, y: 28), size: 10, color: .glassSecondary)
        }
        let chart = NSRect(x: 14, y: 44, width: w - 28, height: 56)
        Draw.chartBackground(chart)
        Draw.area(chart, m.cpuHistory.map { $0.system + $0.user }, scroll: m.scroll, color: .systemBlue, dot: true)
        Draw.area(chart, m.cpuHistory.map { $0.system }, scroll: m.scroll, color: .systemOrange)
        var x: CGFloat = 14
        for (name, key, c) in [("System", "sys", NSColor.systemOrange), ("User", "user", .systemBlue), ("Idle", "idle", .glassTertiary)] {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 112, width: 7, height: 7)).fill()
            Draw.text("\(name) \(Draw.pct(m.v(key)))", NSPoint(x: x + 11, y: 108), size: 11, color: .glassSecondary, mono: true)
            x += (w - 28) / 3
        }
    }

    private func drawGPU(_ w: CGFloat) {
        let m = model
        Draw.title("cpu.fill", "GPU", in: w, tint: .systemGreen)
        Draw.text(m.gpu == nil ? "--" : Draw.pct(m.v("gpu")), NSPoint(x: w - 14, y: 8), size: 20, weight: .semibold, right: true, mono: true)
        if let mem = gpuMemory {   // 显存（Apple 芯片与 CPU 共享内存）
            Draw.text(L("显存 ", "GPU mem ") + SystemInfo.gb(mem), NSPoint(x: 14, y: 28), size: 10, color: .glassSecondary)
        }
        let chart = NSRect(x: 14, y: 44, width: w - 28, height: 60)
        Draw.chartBackground(chart)
        Draw.area(chart, m.gpuHistory, scroll: m.scroll, color: .systemGreen, dot: true)
    }

    private func drawTemps(_ w: CGFloat) {
        let m = model
        Draw.title("thermometer.medium", L("温度", "Temp"), in: w, tint: .systemOrange)   // 半宽卡片：英文用缩写，给散热标签留位置
        // 系统散热状态（macOS 据此决定是否降频）
        let (ttext, tcolor): (String, NSColor) = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:  return (L("正常", "Normal"), .systemGreen)
            case .fair:     return (L("偏热", "Warm"), .systemYellow)
            case .serious:  return (L("很热", "Hot"), .systemOrange)
            case .critical: return (L("过热", "Critical"), .systemRed)
            @unknown default: return ("--", .glassSecondary)
            }
        }()
        let tl = NSAttributedString(string: ttext, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: tcolor])
        let tw = tl.size().width + 12
        tcolor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: w - 14 - tw, y: 12, width: tw, height: 16), xRadius: 8, yRadius: 8).fill()
        tl.draw(at: NSPoint(x: w - 14 - tw + 6, y: 13.5))
        var y: CGFloat = 40
        for (name, key, has) in [(L("芯片", "SoC"), "tSoc", m.temps.soc != nil), (L("电池", "Battery"), "tBat", m.temps.battery != nil), ("SSD", "tSsd", m.temps.ssd != nil)] {
            let c = m.v(key)
            Draw.text(name, NSPoint(x: 14, y: y), size: 11, color: .glassSecondary)
            Draw.text(has ? TempUnit.format(c) : "--", NSPoint(x: w - 14, y: y), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 14, y: y + 17, width: w - 28, height: 4), has ? (c - 20) / 80 : 0, Draw.tempColor(c))
            y += 25
        }
    }

    var memoryPressure = 1
    var gpuMemory: Double?
    var netTotals: (up: Double, down: Double) = (0, 0)

    private func drawMemory(_ w: CGFloat) {
        let m = model
        Draw.title("memorychip", L("内存", "Memory"), in: w, tint: .systemPurple)
        // 内存压力标签
        let level = memoryPressure
        let (ptext, pcolor): (String, NSColor) = level >= 4 ? (L("压力紧张", "Critical"), .systemRed)
            : (level >= 2 ? (L("压力偏高", "Elevated"), .systemOrange) : (L("压力正常", "Normal"), .systemGreen))
        let titleW = NSAttributedString(string: L("内存", "Memory"), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
        let label = NSAttributedString(string: ptext,
                                       attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: pcolor])
        let bx = 14 + 18 + 6 + titleW + 18, bw = label.size().width + 12
        pcolor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: bx, y: 12, width: bw, height: 16), xRadius: 8, yRadius: 8).fill()
        label.draw(at: NSPoint(x: bx + 6, y: 13.5))
        Draw.text("\(SystemInfo.gb(m.v("memUsed"))) / \(SystemInfo.gb(m.memory.total))  \(Draw.pct(m.v("mem")))",
                  NSPoint(x: w - 14, y: 13), size: 11, color: .glassSecondary, right: true, mono: true)
        let bar = NSRect(x: 14, y: 40, width: w - 28, height: 10)
        let shape = NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.16).setFill(); shape.fill()
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
            Draw.text("\(name) \(SystemInfo.gb(v))", NSPoint(x: lx + 11, y: 60), size: 10, color: .glassSecondary, mono: true)
            lx += (w - 28) / 3
        }
    }

    private func drawStorage(_ w: CGFloat) {
        let m = model
        Draw.title("internaldrive", L("存储", "Storage"), in: w, tint: .systemIndigo)
        guard let st = m.storage else { return }
        let f = m.v("disk")
        let center = NSPoint(x: 44, y: 84), r: CGFloat = 26
        let ring = NSBezierPath(); ring.lineWidth = 8
        ring.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        NSColor.labelColor.withAlphaComponent(0.16).setStroke(); ring.stroke()
        let arc = NSBezierPath(); arc.lineWidth = 8; arc.lineCapStyle = .round
        arc.appendArc(withCenter: center, radius: r, startAngle: -90, endAngle: -90 + 360 * CGFloat(f), clockwise: false)
        Draw.level(f).setStroke(); arc.stroke()
        let s = NSAttributedString(string: Draw.pct(f), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        s.draw(at: NSPoint(x: center.x - s.size().width / 2, y: center.y - s.size().height / 2))
        Draw.text(L("已用", "Used"), NSPoint(x: 84, y: 58), size: 10, color: .glassSecondary)
        Draw.text(SystemInfo.gb(st.used), NSPoint(x: 84, y: 71), size: 11, weight: .medium, mono: true)
        Draw.text(L("可用", "Free"), NSPoint(x: 84, y: 88), size: 10, color: .glassSecondary)
        Draw.text(SystemInfo.gb(st.total - st.used), NSPoint(x: 84, y: 101), size: 11, weight: .medium, mono: true)
    }

    private var batteryTime: (label: String, value: String)?
    func updateBatteryTime() { batteryTime = SystemInfo.batteryTime() }

    private func drawBattery(_ w: CGFloat) {
        let m = model
        Draw.title("battery.100", L("电池", "Battery"), in: w, tint: .systemGreen)
        guard let b = m.battery else {
            Draw.text(L("无电池", "No battery"), NSPoint(x: 14, y: 44), size: 11, color: .glassSecondary); return
        }
        let f = m.v("bat")
        let body = NSRect(x: 14, y: 40, width: 46, height: 22)
        let outline = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
        outline.lineWidth = 1.5; NSColor.glassSecondary.setStroke(); outline.stroke()
        NSColor.glassSecondary.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 2, y: body.midY - 4, width: 3, height: 8), xRadius: 1.5, yRadius: 1.5).fill()
        let base: NSColor = b.percent <= 20 ? .systemRed : (b.percent <= 40 ? .systemYellow : .systemGreen)
        // 充电时电量条“呼吸”：亮度随时间起伏
        let pulse = b.state == "charging" ? 0.65 + 0.35 * (0.5 + 0.5 * sin(CACurrentMediaTime() * 3)) : 1
        base.withAlphaComponent(pulse).setFill()
        NSBezierPath(roundedRect: NSRect(x: body.minX + 3, y: body.minY + 3, width: (body.width - 6) * CGFloat(f), height: body.height - 6),
                     xRadius: 3, yRadius: 3).fill()
        if b.state == "charging" { Draw.symbol("bolt.fill", NSPoint(x: body.midX - 6, y: body.minY + 3), size: 11, color: .white) }
        Draw.text(Draw.pct(f), NSPoint(x: w - 14, y: 41), size: 18, weight: .semibold, right: true, mono: true)
        // 右上角：电池温度；标题旁：供电状态小图标（充电 = 闪电，接电源 = 插头）
        if m.temps.battery != nil {
            Draw.text(TempUnit.format(m.v("tBat")), NSPoint(x: w - 14, y: 13), size: 10, weight: .medium, color: .glassSecondary, right: true, mono: true)
        }
        let titleW = 14 + 22 + 6 + NSAttributedString(string: L("电池", "Battery"), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).size().width
        if b.state == "charging" { Draw.symbol("bolt.fill", NSPoint(x: titleW + 4, y: 12), size: 10, color: .systemYellow) }
        else if b.state == "ac"  { Draw.symbol("powerplug.fill", NSPoint(x: titleW + 4, y: 12), size: 10, color: .glassSecondary) }
        if let h = m.health {
            Draw.text(L("健康度", "Health"), NSPoint(x: 14, y: 72), size: 10, color: .glassSecondary)
            Draw.text(Draw.pct(m.v("health")), NSPoint(x: w - 14, y: 71), size: 11, weight: .medium, right: true, mono: true)
            Draw.bar(NSRect(x: 14, y: 87, width: w - 28, height: 4), m.v("health"), m.v("health") >= 0.8 ? .systemGreen : (m.v("health") >= 0.6 ? .systemYellow : .systemRed))
            Draw.text(L("循环次数", "Cycles"), NSPoint(x: 14, y: 96), size: 10, color: .glassSecondary)
            Draw.text("\(h.cycles) / \(h.designCycles)", NSPoint(x: w - 14, y: 95), size: 11, weight: .medium, right: true, mono: true)
        }
        if let t = batteryTime {
            Draw.text(t.label, NSPoint(x: 14, y: 116), size: 10, color: .glassSecondary)
            Draw.text(t.value, NSPoint(x: w - 14, y: 115), size: 11, weight: .medium, right: true)
        }
    }

    private func drawNetwork(_ w: CGFloat) {
        let m = model
        Draw.title("network", L("网络", "Network"), in: w, tint: .systemTeal)
        Draw.text("↓ " + NetMonitor.format(m.v("down")), NSPoint(x: w - 14, y: 13), size: 11, weight: .medium, color: .systemTeal, right: true, mono: true)
        Draw.text("↑ " + NetMonitor.format(m.v("up")), NSPoint(x: w - 120, y: 13), size: 11, weight: .medium, color: .systemPink, right: true, mono: true)
        let chart = NSRect(x: 14, y: 40, width: w - 28, height: 42)
        Draw.chartBackground(chart)
        let peak = max(m.netHistory.map { max($0.up, $0.down) }.max() ?? 0, 10 * 1024)
        Draw.area(chart, m.netHistory.map { $0.down / peak }, scroll: m.scroll, color: .systemTeal, dot: true)
        Draw.area(chart, m.netHistory.map { $0.up / peak }, scroll: m.scroll, color: .systemPink, line: true)
        Draw.text(L("峰值 ", "Peak ") + NetMonitor.format(peak), NSPoint(x: chart.maxX - 6, y: chart.minY + 3), size: 9, color: .glassTertiary, right: true, mono: true)
        func bytes(_ b: Double) -> String { b >= 1_073_741_824 ? String(format: "%.2f GB", b / 1_073_741_824) : String(format: "%.0f MB", b / 1_048_576) }
        Draw.text(L("本次 ", "Session ") + "↑ " + bytes(netTotals.up) + "  ↓ " + bytes(netTotals.down),
                  NSPoint(x: chart.minX + 6, y: chart.minY + 3), size: 9, color: .glassTertiary, mono: true)
    }
}

// MARK: - 设置窗口（SwiftUI 分组表单，macOS 26 上自带液态玻璃风格）
final class SettingsModel: ObservableObject {
    @Published var values: [String: String]
    @Published var login: Bool
    @Published var langTick = 0                       // 语言切换后强制刷新文字
    var apply: (String, String) -> Void = { _, _ in }
    var setLogin: (Bool) -> Bool = { $0 }
    var options: (String) -> [(id: String, name: String)] = { _ in [] }
    var openActivityMonitor: () -> Void = {}
    let runnerFrames: [String: [NSImage]] = Dictionary(uniqueKeysWithValues: Runner.all.map { ($0.id, $0.frames()) })

    init(values: [String: String], login: Bool) { self.values = values; self.login = login }

    func binding(_ key: String) -> Binding<String> {
        Binding(get: { self.values[key] ?? "" }, set: { v in self.values[key] = v; self.apply(key, v) })
    }
}

/// Runner 选择卡片：会动的预览 + 名字，选中时高亮
struct RunnerCard: View {
    let runner: Runner
    let frames: [NSImage]
    let selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let i = Int(ctx.date.timeIntervalSinceReferenceDate * 10) % max(frames.count, 1)
                Image(nsImage: frames[i])
                    .renderingMode(runner.template ? .template : .original)
                    .interpolation(.none)
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
                    .frame(height: 30)
            }
            .frame(width: 70, height: 38)
            Text(runner.displayName).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8).frame(width: 84)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    var width: CGFloat = 540
    var height: CGFloat = 770

    private func menuPicker(_ key: String, _ title: String, _ icon: String) -> some View {
        Picker(selection: m.binding(key)) {
            ForEach(m.options(key), id: \.id) { o in Text(o.name).tag(o.id) }
        } label: { Label(title, systemImage: icon) }
        .pickerStyle(.menu)
    }

    private func segmented(_ key: String, _ title: String, _ icon: String) -> some View {
        Picker(selection: m.binding(key)) {
            ForEach(m.options(key), id: \.id) { o in Text(o.name).tag(o.id) }
        } label: { Label(title, systemImage: icon) }
        .pickerStyle(.segmented)
    }

    var body: some View {
        let _ = m.langTick
        Form {
            Section(L("外观", "Appearance")) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Runner", systemImage: "figure.run")
                    // 自动换行：面板里一行 3 张，宽窗口里一行 5 张
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: 8)], spacing: 8) {
                        ForEach(Runner.all, id: \.id) { r in
                            RunnerCard(runner: r, frames: m.runnerFrames[r.id] ?? [], selected: m.values["runner"] == r.id)
                                .onTapGesture { withAnimation(.snappy) { m.binding("runner").wrappedValue = r.id } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                menuPicker("barMetric", L("菜单栏显示", "Menu Bar Shows"), "menubar.rectangle")
                menuPicker("barStyle", L("菜单栏样式", "Menu Bar Style"), "chart.xyaxis.line")
                menuPicker("speedSource", L("Runner 速度跟随", "Runner Speed Follows"), "speedometer")
            }
            Section(L("数据", "Data")) {
                segmented("refreshInterval", L("刷新频率", "Refresh Rate"), "arrow.clockwise")
                segmented("tempUnit", L("温度单位", "Temperature Unit"), "thermometer.medium")
                menuPicker("lang", "语言 / Language", "globe")
            }
            Section(L("系统", "System")) {
                Toggle(isOn: Binding(get: { m.login }, set: { m.login = m.setLogin($0) })) {
                    Label(L("开机自动启动", "Launch at Login"), systemImage: "power")
                }
                Button { m.openActivityMonitor() } label: {
                    Label(L("打开活动监视器", "Open Activity Monitor"), systemImage: "waveform.path.ecg")
                }
                LabeledContent {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--").foregroundStyle(.secondary)
                } label: { Label(L("版本", "Version"), systemImage: "info.circle") }
                LabeledContent {
                    Link("HeadmasterEggy/MenuRunner", destination: URL(string: "https://github.com/HeadmasterEggy/MenuRunner")!)
                } label: { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label(L("退出 MenuRunner", "Quit MenuRunner"), systemImage: "xmark.circle")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)          // 透出面板的液态玻璃
        .frame(width: width, height: height)
    }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let cpu = CPUMonitor()
    private let netMon = NetMonitor()
    private let tempMon = TempMonitor.shared
    private let model = StatsModel()
    private lazy var panel = PanelController(model: model)
    private var runner = Runner.all.first { $0.id == UserDefaults.standard.string(forKey: "runner") } ?? Runner.coffee   // 默认咖啡
    private lazy var frames = runner.frames(appearance: statusItem.button?.effectiveAppearance)
    private var appearanceObservation: NSKeyValueObservation?
    private var lastDark: Bool?
    private var lastTemps: Temps?
    private var lastTempsAt: CFTimeInterval = 0
    private var frameIndex = 0
    private var animTimer: Timer?
    private var sampleTimer: Timer?
    private var usage = 0.0
    private var runLevel = 0

    /// 菜单栏文字显示什么
    /// 菜单栏旁边显示什么；默认不显示（只有 runner 图标）
    private var barMetric = UserDefaults.standard.string(forKey: "barMetric") ?? "none"
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
        button.image = NSImage(size: frames[0].size)   // 透明占位，runner 由 runLayer 播放
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        buildSettingsMenu()
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] b, _ in
            // 彩色 runner 的猫身颜色随深浅色变；只在深 / 浅真正切换时重画（这个通知会频繁触发）
            guard let self else { return }
            let dark = b.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            guard dark != self.lastDark else { return }
            self.lastDark = dark
            self.frames = self.runner.frames(appearance: b.effectiveAppearance, level: self.runLevel)
            self.installRunAnimation()                 // 单色 runner 重新上色（深色 → 白，浅色 → 黑）
        }
        installRunAnimation()
        // 存储页要用的各应用大小：启动后在后台慢慢算好
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.panel.detail.prewarmStorage() }
        panel.onSettings = { [weak self] _ in self?.showSettings() }   // 齿轮 → 设置窗口

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

        if CommandLine.arguments.contains("--settings-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showSettings() }
        }
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.popSettings(from: button) }
        }
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.panel.show(below: button)
                NSLog("panel debug: shown=%d", self.panel.isVisible ? 1 : 0)
                if let i = CommandLine.arguments.firstIndex(of: "--detail"), i + 1 < CommandLine.arguments.count {
                    let map: [String: DetailKind] = ["system": .system, "cpu": .cpu, "gpu": .gpu, "memory": .memory, "temps": .temps,
                                                     "storage": .storage, "battery": .battery, "network": .network]
                    if let k = map[CommandLine.arguments[i + 1]] { self.panel.debugShow(k) }
                }
            }
        }
    }

    /// 面板打开时 0.5 秒采样一次（接近实时，中间由 60fps 动画补间），关闭时 1.5 秒一次省电
    func applicationWillTerminate(_ n: Notification) { panel.detail.stopNetwork() }   // 退出时结束 nettop

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
        let open = NSMenuItem(title: L("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        open.target = self; open.image = icon("gearshape")
        settingsMenu.addItem(open)
        settingsMenu.addItem(.separator())
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
        apply(pair[0], pair[1])
    }

    /// 菜单和设置窗口共用：应用一项设置，并让两边的显示保持一致
    private func apply(_ key: String, _ id: String) {
        submenus[key]?.items.forEach { $0.state = (($0.representedObject as? [String])?.last == id) ? .on : .off }
        if settingsModel.values[key] != id { settingsModel.values[key] = id }
        switch key {
        case "runner":
            guard let r = Runner.all.first(where: { $0.id == id }) else { return }
            runner = r; runLevel = 0; frames = r.frames(appearance: statusItem.button?.effectiveAppearance); frameIndex = 0
            UserDefaults.standard.set(id, forKey: "runner")
            updateStatusImage()
            installRunAnimation()
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
            settingsModel.langTick += 1
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

    // MARK: 设置窗口
    private lazy var settingsModel: SettingsModel = {
        let m = SettingsModel(values: [
            "runner": runner.id, "barMetric": barMetric, "barStyle": barStyle, "speedSource": speedSource,
            "refreshInterval": String(format: "%.1f", refreshInterval), "tempUnit": TempUnit.fahrenheit ? "F" : "C", "lang": Lang.mode,
        ], login: SMAppService.mainApp.status == .enabled)
        m.apply = { [weak self] k, v in self?.apply(k, v) }
        m.options = { key in
            switch key {
            case "barMetric": return Self.barOptions.map { ($0.0, $0.1) }
            case "barStyle": return Self.styleOptions.map { ($0.0, $0.1) }
            case "speedSource": return [("cpu", "CPU"), ("gpu", "GPU"), ("memory", L("内存", "Memory"))]
            case "refreshInterval": return [("0.5", L("0.5 秒", "0.5s")), ("1.0", L("1 秒", "1s")), ("2.0", L("2 秒", "2s"))]   // 面板窄，用短名
            case "tempUnit": return [("C", "°C"), ("F", "°F")]
            case "lang": return Self.langOptions.map { ($0.0, $0.1) }
            default: return []
            }
        }
        m.setLogin = { [weak self] on in
            let svc = SMAppService.mainApp
            do { if on { try svc.register() } else { try svc.unregister() } } catch { NSLog("Login item error: \(error)") }
            if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            self?.buildSettingsMenu()
            return svc.status == .enabled
        }
        m.openActivityMonitor = { [weak self] in self?.openActivityMonitor() }
        return m
    }()
    /// 打开面板并滑到设置页
    @objc private func showSettings() {
        panel.settingsModel = settingsModel
        if !panel.isVisible, let button = statusItem.button { panel.show(below: button) }
        settingsModel.login = SMAppService.mainApp.status == .enabled
        panel.showSettings()
    }

    private func popSettings(from view: NSView) {
        settingsMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private func sample() {
        let l = cpu.load()
        usage = l.total
        let needTemps = panel.isVisible || barMetric == "temp" || barMetric == "batTemp"
        // 温度每 2 秒最多读一次（读一次 ~30ms，温度也不会变那么快）
        if lastTemps == nil || (needTemps && CACurrentMediaTime() - lastTempsAt >= 2) { lastTemps = tempMon.read(); lastTempsAt = CACurrentMediaTime() }
        let g = GPUMonitor.usage(), m = SystemInfo.memory(), n = netMon.rate(), t = lastTemps ?? Temps()
        switch speedSource {           // Runner 跟随哪个指标变快
        case "gpu":    usage = g ?? 0
        case "memory": usage = m.used / m.total
        default:       usage = l.total
        }
        let bat = SystemInfo.battery()
        panel.updateBatteryTime()
        panel.sampleMain()
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
        // 悬停菜单栏图标的摘要
        var tip = ["CPU " + pct(l.total), L("内存 ", "Memory ") + pct(m.used / m.total)]
        if let g { tip.append("GPU " + pct(g)) }
        if let soc = t.soc { tip.append(L("温度 ", "Temp ") + TempUnit.format(soc, decimals: 0)) }
        if let bat { tip.append(L("电池 ", "Battery ") + "\(bat.percent)%") }
        statusItem.button?.toolTip = tip.joined(separator: " · ")
        if panel.isVisible {
            panel.gpuMemory = GPUMonitor.memoryInUse()
            panel.netTotals = (netMon.totalUp, netMon.totalDown)
        }
        updateStatusImage()
        scheduleAnimation()
    }

    // MARK: 菜单栏动态小图标（单色模板图，随深浅色菜单栏自动变色）
    /// 按钮图片：runner 的位置留空（由 runLayer 播放动画），右侧可选的迷你图表。只在采样时更新，不再每帧更新
    private func updateStatusImage() {
        let rf = frames[frameIndex]
        let placeholder = NSImage(size: rf.size)                 // 透明占位：保留宽度，runner 由图层画
        guard barStyle != "text", barMetric != "none" else {
            statusItem.button?.image = placeholder; layoutRunLayer(); return
        }
        let gw: CGFloat
        switch barMetric {
        case "battery": gw = 22
        case "temp", "batTemp": gw = 9
        default: gw = 26
        }
        let h = max(rf.size.height, 18)
        let size = NSSize(width: rf.size.width + 4 + gw, height: h)
        let img = NSImage(size: size, flipped: false) { [weak self] _ in
            self?.drawMini(in: NSRect(x: rf.size.width + 4, y: (h - 14) / 2, width: gw, height: 14))
            return true
        }
        img.isTemplate = true
        statusItem.button?.image = img
        layoutRunLayer()
    }

    // MARK: 图层动画：动画由系统渲染服务器播放，app 每帧不需要做任何事
    // （之前每帧换按钮图片，macOS 每次都要重排菜单栏并把图标截图复制到每块显示器，占 ~1% CPU / 帧率）
    private let runLayer = CALayer()
    private var runFps: Double = 0

    /// 单色 runner 按菜单栏深浅色上色；彩色 runner 原样
    private func cgFrames() -> [CGImage] {
        let appearance = statusItem.button?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return frames.compactMap { img in
            let scale: CGFloat = 2, size = img.size
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .none
            img.draw(in: NSRect(origin: .zero, size: size))
            if runner.template {
                appearance.performAsCurrentDrawingAppearance {
                    NSColor.labelColor.setFill()
                    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep.cgImage
        }
    }

    private func installRunAnimation() {
        guard let button = statusItem.button else { return }
        if runLayer.superlayer == nil {
            button.wantsLayer = true
            runLayer.magnificationFilter = .nearest
            runLayer.contentsGravity = .resize
            button.layer?.addSublayer(runLayer)
        }
        let cg = cgFrames()
        guard !cg.isEmpty else { return }
        runLayer.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        runLayer.contents = cg[0]
        CATransaction.commit()
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = cg
        anim.calculationMode = .discrete
        anim.duration = Double(cg.count)          // 速率 1 = 每秒 1 帧；真实帧率由 layer.speed 控制
        anim.repeatCount = .infinity
        runLayer.beginTime = 0; runLayer.timeOffset = 0
        runLayer.add(anim, forKey: "run")
        if runFps > 0 { setRunSpeed(runFps, force: true) }
        layoutRunLayer()
    }

    /// 改变播放速率而不跳帧：把当前进度记进 timeOffset 再换速度
    private func setRunSpeed(_ fps: Double, force: Bool = false) {
        guard force || abs(fps - runFps) > 0.05 else { return }
        runFps = fps
        let now = CACurrentMediaTime()
        let local = runLayer.convertTime(now, from: nil)
        runLayer.speed = Float(fps)
        runLayer.timeOffset = local
        runLayer.beginTime = now
    }

    /// 让图层对准按钮里图片（占位）所在的位置
    private func layoutRunLayer() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let b = self.statusItem.button, let cell = b.cell as? NSButtonCell else { return }
            let r = cell.imageRect(forBounds: b.bounds)
            let size = self.frames.first?.size ?? .zero
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.runLayer.frame = CGRect(x: r.minX, y: r.midY - size.height / 2, width: size.width, height: size.height)
            CATransaction.commit()
        }
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

    /// CPU 越高跑得越快：0% → 4 帧/秒，50% → 16，100% → 25（两段指数变化）
    private func scheduleAnimation() {
        // 跟随占用率，按“倍数”变化（人眼感知速度看的是快了几倍）：前半段 4 → 16 涨得快，后半段 16 → 25 放缓，高占用时不至于太晃
        // 动画由图层在渲染服务器里播放，帧率高低几乎不影响 CPU
        let u = min(max(usage, 0), 1)
        let fps = u <= 0.5 ? 4 * pow(4, u * 2) : 16 * pow(25.0 / 16, u * 2 - 1)
        // 分档 runner：越过档位边界 0.1 才换档，避免占用率在边界附近抖动时反复换帧
        let raw = u * Double(runner.levels)
        if runner.levels > 1, abs(raw - (Double(runLevel) + 0.5)) > 0.6 {
            runLevel = min(Int(raw), runner.levels - 1)
            frames = runner.frames(appearance: statusItem.button?.effectiveAppearance, level: runLevel)
            installRunAnimation()
        }
        let interval = 1 / fps
        if CommandLine.arguments.contains("--fps-log") { NSLog("fps debug: usage=%.0f%% fps=%.1f", u * 100, fps) }
        _ = interval
        setRunSpeed(fps)
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
    print("battery time", SystemInfo.batteryTime().map { "\($0.label): \($0.value)" } ?? "nil", "estimate", IOPSGetTimeRemainingEstimate())
    print("health", SystemInfo.batteryHealth().map { "\(Draw.pct($0.health)) cycles \($0.cycles)/\($0.designCycles)" } ?? "nil")
    print("temps soc", t.soc.map { String(format: "%.1f", $0) } ?? "nil", "battery", t.battery.map { String(format: "%.1f", $0) } ?? "nil",
          "ssd", t.ssd.map { String(format: "%.1f", $0) } ?? "nil")
    print("network up", NetMonitor.format(nr.up), "down", NetMonitor.format(nr.down))
    for a in ProcessMemory.top(10) { print("  mem", ProcessMemory.format(a.bytes), "×\(a.processes)", a.name) }
    exit(0)
}

// MenuRunner --runner <id> out.png：单个 runner 放大 12 倍，每档两行：深色背景、浅色背景
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--runner",
   let r = Runner.all.first(where: { $0.id == CommandLine.arguments[2] }) {
    let sc: CGFloat = 12, fw = r.size.width * sc, fh = r.size.height * sc
    let sheet = NSImage(size: NSSize(width: fw * CGFloat(r.frameCount), height: fh * 2 * CGFloat(r.levels)), flipped: true) { _ in
        for level in 0..<r.levels {
            let frames = r.frames(level: level)
            for (k, bg) in [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.93, alpha: 1)].enumerated() {
                let row = level * 2 + k
                bg.setFill(); NSRect(x: 0, y: CGFloat(row) * fh, width: fw * CGFloat(frames.count), height: fh).fill()
                NSGraphicsContext.current?.imageInterpolation = .none
                for (i, img) in frames.enumerated() {
                    img.draw(in: NSRect(x: CGFloat(i) * fw, y: CGFloat(row) * fh, width: fw, height: fh), from: .zero,
                             operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
        }
        return true
    }
    let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    exit(0)
}

// MenuRunner --bench：每项采样跑 20 次，打印平均耗时
if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--bench" {
    func bench(_ name: String, _ f: () -> Void) {
        let t0 = CACurrentMediaTime(); for _ in 0..<20 { f() }
        print(String(format: "%-16@ %7.2f ms", name as NSString, (CACurrentMediaTime() - t0) / 20 * 1000))
    }
    let c = CPUMonitor(), n = NetMonitor(), tm = TempMonitor.shared
    bench("cpu") { _ = c.load() }
    bench("gpu") { _ = GPUMonitor.usage() }
    bench("memory") { _ = SystemInfo.memory() }
    bench("storage") { _ = SystemInfo.storage() }
    bench("battery") { _ = SystemInfo.battery() }
    bench("health") { _ = SystemInfo.batteryHealth() }
    bench("batteryTime") { _ = SystemInfo.batteryTime() }
    bench("temps") { _ = tm.read() }
    bench("network") { _ = n.rate() }
    bench("pressure") { _ = SystemInfo.memoryPressure() }
    let frames = Runner.coffee.frames()
    bench("coffee frames") { _ = Runner.coffee.frames() }
    _ = frames
    exit(0)
}

// MenuRunner --icon out.iconset：生成 app 图标（夜空渐变 + 像素橘猫火箭），再用 iconutil 打包成 .icns
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--icon" {
    let dir = CommandLine.arguments[2]
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let sprite = Runner.rocketCat.frames()[1]                  // 选一帧尾焰较长的
    func render(_ px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let k = CGFloat(px) / 1024
        // Apple 图标模板：1024 画布里 824×824 的圆角方形，圆角 185
        let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let shape = NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 24 * k; shadow.shadowOffset = NSSize(width: 0, height: -10 * k); shadow.set()
        NSColor.black.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        shape.addClip()
        // 夜空渐变 + 中间的光晕
        NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.22, blue: 0.62, alpha: 1),
                            NSColor(srgbRed: 0.10, green: 0.12, blue: 0.32, alpha: 1)])!.draw(in: body, angle: -90)
        NSGradient(colors: [NSColor(srgbRed: 1, green: 0.62, blue: 0.30, alpha: 0.30), NSColor(srgbRed: 1, green: 0.62, blue: 0.30, alpha: 0)])!
            .draw(fromCenter: NSPoint(x: 540 * k, y: 500 * k), radius: 0, toCenter: NSPoint(x: 540 * k, y: 500 * k), radius: 380 * k, options: [])
        // 星星（固定位置）
        let stars: [(CGFloat, CGFloat, CGFloat)] = [(190, 780, 10), (300, 860, 6), (760, 830, 9), (850, 700, 6), (230, 300, 7),
                                                    (820, 250, 10), (640, 860, 5), (150, 560, 5), (880, 470, 5), (420, 190, 6)]
        for (x, y, r) in stars {
            NSColor(srgbRed: 1, green: 0.93, blue: 0.75, alpha: 0.9).setFill()
            if r >= 9 {   // 大星星画成十字
                NSRect(x: (x - r * 1.6) * k, y: (y - r * 0.35) * k, width: r * 3.2 * k, height: r * 0.7 * k).fill()
                NSRect(x: (x - r * 0.35) * k, y: (y - r * 1.6) * k, width: r * 0.7 * k, height: r * 3.2 * k).fill()
            } else {
                NSBezierPath(ovalIn: NSRect(x: (x - r / 2) * k, y: (y - r / 2) * k, width: r * k, height: r * k)).fill()
            }
        }
        // 像素橘猫火箭：最近邻放大，保持像素格清晰
        NSGraphicsContext.current?.imageInterpolation = .none
        let sw: CGFloat = 36 * 21 * k, sh: CGFloat = 20 * 21 * k
        let dst = NSRect(x: 512 * k - sw / 2, y: 505 * k - sh / 2, width: sw, height: sh)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        glow.shadowBlurRadius = 18 * k; glow.shadowOffset = NSSize(width: 0, height: -14 * k); glow.set()
        sprite.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                       ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
    }
    exit(0)
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--preview" {
    let maxFrames = 15                                   // 帧多的 runner（心电图 45 帧）只画前 15 帧，图别太宽
    let sc = 8.0, w = Runner.all.map { $0.size.width * CGFloat(min($0.frameCount, maxFrames)) }.max()!
    let rowH = 22.0, rows = Double(Runner.all.count)
    let sheet = NSImage(size: NSSize(width: w * sc, height: rowH * sc * rows), flipped: true) { _ in
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w * sc, height: rowH * sc * rows).fill()
        for (row, r) in Runner.all.enumerated() {
            for (i, f) in r.frames().prefix(maxFrames).enumerated() {
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

// 调试：MenuRunner --render out.png  离屏渲染主面板（左浅色 / 右深色；玻璃用近似底色代替）
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render" {
    _ = NSApplication.shared
    let model = StatsModel(), cpu = CPUMonitor(), net = NetMonitor()
    _ = cpu.load(); _ = net.rate(); Thread.sleep(forTimeInterval: 0.6)
    for _ in 0..<3 {
        model.update(cpu: cpu.load(), gpu: GPUMonitor.usage(), memory: SystemInfo.memory(), storage: SystemInfo.storage(),
                     battery: SystemInfo.battery(), health: SystemInfo.batteryHealth(), temps: TempMonitor.shared.read(), net: net.rate())
        Thread.sleep(forTimeInterval: 0.3)
    }
    model.tick(dt: 10)
    let panel = PanelController(model: model)
    panel.updateBatteryTime()
    panel.memoryPressure = SystemInfo.memoryPressure()
    panel.gpuMemory = GPUMonitor.memoryInUse()
    panel.netTotals = (net.totalUp, net.totalDown)
    panel.detail.refresh(.cpu); Thread.sleep(forTimeInterval: 0.8); panel.detail.refresh(.cpu)
    let v = panel.debugMainView, sz = v.frame.size
    let sheet = NSImage(size: NSSize(width: sz.width * 2 + 20, height: sz.height), flipped: false) { _ in
        for (i, name) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
            let ox = CGFloat(i) * (sz.width + 20)
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                (i == 0 ? NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.93, alpha: 1) : NSColor(white: 0.12, alpha: 1)).setFill()
                NSRect(x: ox, y: 0, width: sz.width, height: sz.height).fill()
                for f in panel.debugCardFrames {   // 近似玻璃底色
                    (i == 0 ? NSColor.white.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.08)).setFill()
                    NSBezierPath(roundedRect: f.offsetBy(dx: ox, dy: 0), xRadius: 18, yRadius: 18).fill()
                }
            }
            v.appearance = NSAppearance(named: name)
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            rep.draw(in: NSRect(x: ox, y: 0, width: sz.width, height: sz.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        return true
    }
    let out = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不显示 Dock 图标
app.run()
