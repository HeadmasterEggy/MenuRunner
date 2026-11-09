import Foundation
import IOKit
import QuartzCore

struct PowerReading {
    var system: Double?
    var perPid: [pid_t: Double]
    var cpuPerPid: [pid_t: Double]
    var memoryPerPid: [pid_t: Double]
    var interval: Double
}

private struct ProcessUsage { var energy: UInt64, cpuTime: UInt64, footprint: UInt64 }

final class PowerMonitor {
    private static let nanojoulesPerJoule = 1e9
    private static let nanosPerSecond = 1e9
    private static let milliPerUnit = 1000.0
    private static let microPerUnit = 1_000_000.0
    private static let plausibleWatts = 0.05...2000

    private var prev: [pid_t: ProcessUsage] = [:]
    private var prevTime: CFTimeInterval = 0
    private let nanosPerTick: Double = { var tb = mach_timebase_info(); mach_timebase_info(&tb); return Double(tb.numer) / Double(tb.denom) }()

    func read() -> PowerReading? {
        let now = CACurrentMediaTime()
        let dt = now - prevTime
        var cur: [pid_t: ProcessUsage] = [:], watts: [pid_t: Double] = [:], cores: [pid_t: Double] = [:], memory: [pid_t: Double] = [:]
        for pid in AppIdentity.allPids() {
            guard let u = Self.usage(pid) else { continue }
            cur[pid] = u
            memory[pid] = Double(u.footprint)
            guard let p = prev[pid], dt > 0 else { continue }
            if u.energy > p.energy { watts[pid] = Double(u.energy - p.energy) / Self.nanojoulesPerJoule / dt }
            if u.cpuTime > p.cpuTime { cores[pid] = Double(u.cpuTime - p.cpuTime) * nanosPerTick / Self.nanosPerSecond / dt }
        }
        let first = prev.isEmpty
        prev = cur
        prevTime = now
        return first ? nil : PowerReading(system: Self.systemWatts(), perPid: watts, cpuPerPid: cores, memoryPerPid: memory, interval: dt)
    }

    private static func usage(_ pid: pid_t) -> ProcessUsage? {
        var u = rusage_info_current()
        let r = withUnsafeMutablePointer(to: &u) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
        }
        return r == 0 ? ProcessUsage(energy: u.ri_energy_nj, cpuTime: u.ri_user_time + u.ri_system_time, footprint: u.ri_phys_footprint) : nil
    }

    static func systemWatts() -> Double? {
        if let w = SMC.shared.number("PSTR"), plausibleWatts.contains(w) { return w }
        return batteryWatts()
    }

    private static func batteryWatts() -> Double? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        func number(_ k: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
        }
        if let t = IORegistryEntryCreateCFProperty(svc, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
           let mw = (t["SystemPowerIn"] as? NSNumber)?.doubleValue, plausibleWatts.contains(mw / milliPerUnit) {
            return mw / milliPerUnit
        }
        guard let mv = number("Voltage")?.doubleValue, let amps = number("InstantAmperage") ?? number("Amperage") else { return nil }
        let ma = Double(Int64(truncatingIfNeeded: amps.int64Value))
        guard ma < 0 else { return nil }
        let w = mv * -ma / microPerUnit
        return plausibleWatts.contains(w) ? w : nil
    }

    static func formatWatts(_ w: Double) -> String {
        w < 1 ? String(format: "%.2f W", w) : (w < 10 ? String(format: "%.1f W", w) : String(format: "%.0f W", w))
    }

    static func formatEnergy(_ joules: Double) -> String {
        let wh = joules / 3600
        return wh < 1 ? String(format: "%.0f mWh", wh * milliPerUnit) : (wh < 10 ? String(format: "%.2f Wh", wh) : String(format: "%.1f Wh", wh))
    }
}
