import Foundation

struct Fan {
    var index: Int
    var rpm: Double
    var minRpm: Double
    var maxRpm: Double

    var fraction: Double { maxRpm > 0 ? min(max(rpm / maxRpm, 0), 1) : 0 }
    var name: String { L("风扇 \(index + 1)", "Fan \(index + 1)") }
}

final class FanMonitor {
    static let shared = FanMonitor()
    private static let maxFans = 8
    private static let fallbackMaxRpm: Double = 6000

    let count: Int
    var hasFans: Bool { count > 0 }

    private init() {
        let n = Int(SMC.shared.number("FNum") ?? 0)
        count = min(max(n, 0), Self.maxFans)
    }

    func read() -> [Fan] {
        (0..<count).compactMap { i in
            guard let rpm = SMC.shared.number("F\(i)Ac") else { return nil }
            let lo = SMC.shared.number("F\(i)Mn") ?? 0
            let hi = SMC.shared.number("F\(i)Mx").flatMap { $0 > lo ? $0 : nil } ?? Self.fallbackMaxRpm
            return Fan(index: i, rpm: max(rpm, 0), minRpm: lo, maxRpm: hi)
        }
    }

    static func average(_ fans: [Fan]) -> Double? {
        fans.isEmpty ? nil : fans.map(\.rpm).reduce(0, +) / Double(fans.count)
    }

    static func peakFraction(_ fans: [Fan]) -> Double {
        fans.map(\.fraction).max() ?? 0
    }

    static func label(_ rpm: Double, stopped: Bool) -> String {
        stopped ? L("停转", "Stopped") : format(rpm)
    }

    static func format(_ rpm: Double, unit: Bool = true) -> String {
        String(format: "%.0f", rpm) + (unit ? " RPM" : "")
    }
}
