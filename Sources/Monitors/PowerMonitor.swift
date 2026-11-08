import Foundation
import IOKit
import QuartzCore

struct PowerReading {
    var system: Double?
    var perPid: [pid_t: Double]
    var interval: Double
}

final class PowerMonitor {
    private static let nanojoulesPerJoule = 1e9
    private static let milliPerUnit = 1000.0
    private static let microPerUnit = 1_000_000.0
    private static let plausibleWatts = 0.05...2000

    private var prevEnergy: [pid_t: UInt64] = [:]
    private var prevTime: CFTimeInterval = 0

    func read() -> PowerReading? {
        let now = CACurrentMediaTime()
        let dt = now - prevTime
        var cur: [pid_t: UInt64] = [:], watts: [pid_t: Double] = [:]
        for pid in AppIdentity.allPids() {
            guard let e = Self.energy(pid) else { continue }
            cur[pid] = e
            if let p = prevEnergy[pid], e > p, dt > 0 { watts[pid] = Double(e - p) / Self.nanojoulesPerJoule / dt }
        }
        let first = prevEnergy.isEmpty
        prevEnergy = cur
        prevTime = now
        return first ? nil : PowerReading(system: Self.systemWatts(), perPid: watts, interval: dt)
    }

    static func energy(_ pid: pid_t) -> UInt64? {
        var u = rusage_info_current()
        let r = withUnsafeMutablePointer(to: &u) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
        }
        return r == 0 ? u.ri_energy_nj : nil
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
