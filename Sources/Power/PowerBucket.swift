import Foundation

struct AppEnergy: Codable {
    var name: String
    var path: String?
    var joules: Double
}

struct PowerBucket: Codable {
    var start: Date
    var seconds: Double
    var systemWatts: Double?
    var cpu: Double
    var gpu: Double
    var memory: Double
    var socTemp: Double?
    var socTempMax: Double?
    var fanRpm: Double?
    var battery: Int?
    var source: String?
    var apps: [AppEnergy]

    var end: Date { start.addingTimeInterval(seconds) }
}

struct PowerAccumulator {
    private static let maxReadingSeconds = 60.0

    let start: Date
    private var samples = 0
    private var cpu = 0.0, gpu = 0.0, memory = 0.0
    private var socSum = 0.0, socCount = 0, socMax: Double?
    private var fanSum = 0.0, fanCount = 0
    private var battery: Int?, source: String?
    private var powerSeconds = 0.0, systemJoules = 0.0, systemSeconds = 0.0
    private var apps: [String: AppEnergy] = [:]

    init(start: Date) { self.start = start }

    var isEmpty: Bool { samples == 0 && powerSeconds == 0 }

    mutating func add(_ s: Sample) {
        samples += 1
        cpu += s.load.total
        gpu += s.gpu ?? 0
        memory += s.memory.total > 0 ? s.memory.used / s.memory.total : 0
        if let t = s.temps.soc {
            socSum += t; socCount += 1
            socMax = max(socMax ?? t, t)
        }
        if let rpm = FanMonitor.average(s.fans) { fanSum += rpm; fanCount += 1 }
        if let b = s.battery { battery = b.percent; source = b.state }
    }

    mutating func add(system: Double?, apps grouped: [AppStat], interval: Double) {
        let seconds = min(interval, Self.maxReadingSeconds)
        powerSeconds += seconds
        if let w = system { systemJoules += w * seconds; systemSeconds += seconds }
        for a in grouped {
            let key = a.path ?? a.name
            var e = apps[key] ?? AppEnergy(name: a.name, path: a.path, joules: 0)
            e.joules += a.value * interval
            apps[key] = e
        }
    }

    func bucket(appLimit: Int) -> PowerBucket? {
        guard !isEmpty else { return nil }
        let n = Double(max(samples, 1))
        return PowerBucket(
            start: start,
            seconds: max(powerSeconds, 1),
            systemWatts: systemSeconds > 0 ? systemJoules / systemSeconds : nil,
            cpu: cpu / n, gpu: gpu / n, memory: memory / n,
            socTemp: socCount > 0 ? socSum / Double(socCount) : nil, socTempMax: socMax,
            fanRpm: fanCount > 0 ? fanSum / Double(fanCount) : nil,
            battery: battery, source: source,
            apps: Array(apps.values.sorted { $0.joules > $1.joules }.prefix(appLimit)))
    }
}
