import AppKit
import QuartzCore
import IOKit.ps
import IOKit

enum SystemInfo {
    struct Memory { var used = 0.0, total = 1.0, app = 0.0, wired = 0.0, compressed = 0.0 }

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
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                if let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                   let m = d[kIOPSTimeToEmptyKey] as? Int, m > 0 { return (left, fmt(m)) }
            }
        }
        let est = IOPSGetTimeRemainingEstimate()
        if est > 0 { return (left, fmt(Int(est / 60))) }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        defer { if svc != 0 { IOObjectRelease(svc) } }
        func num(_ k: String) -> NSNumber? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber }
        for k in ["AvgTimeToEmpty", "TimeRemaining"] {
            if let m = num(k)?.intValue, m > 0, m < 65535 { return (left, fmt(m)) }
        }
        let ma = Double(Int32(truncatingIfNeeded: num("InstantAmperage")?.int64Value ?? num("Amperage")?.int64Value ?? 0))
        let data = IORegistryEntryCreateCFProperty(svc, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        let full = num("NominalChargeCapacity")?.doubleValue ?? (data?["NominalChargeCapacity"] as? NSNumber)?.doubleValue
        if let full, ma < -50 {
            return (left, "≈ " + fmt(Int(full * Double(b.percent) / 100 / -ma * 60)))
        }
        return (L("预计可用", "Time left"), L("计算中…", "Calculating…"))
    }

    static func memoryPressure() -> Int {
        var v: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &v, &size, nil, 0) == 0 ? Int(v) : 1
    }

    static func gb(_ bytes: Double) -> String { String(format: "%.1f GB", bytes / 1_073_741_824) }
}

struct BatteryHealth { var health: Double, cycles: Int, designCycles: Int }

extension SystemInfo {
    static func batteryHealth() -> BatteryHealth? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        func int(_ k: String) -> Int? {
            IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        let data = IORegistryEntryCreateCFProperty(svc, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] ?? [:]
        func any(_ k: String) -> Int? { int(k) ?? data[k] as? Int }
        guard let design = any("DesignCapacity"), design > 0,
              let nominal = any("NominalChargeCapacity") ?? any("AppleRawMaxCapacity"),
              let cycles = any("CycleCount") else { return nil }
        return BatteryHealth(health: min(Double(nominal) / Double(design), 1), cycles: cycles, designCycles: int("DesignCycleCount9C") ?? 1000)
    }
}
