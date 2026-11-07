import AppKit
import IOKit

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
