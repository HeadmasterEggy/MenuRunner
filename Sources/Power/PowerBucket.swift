import Foundation

struct AppEnergy: Codable {
    var name: String
    var path: String?
    var joules: Double
    var cpuSeconds: Double?
    var peakMemory: Double?
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
    var netUp: Double?
    var netDown: Double?
    var pressure: Double?
    var batteryTemp: Double?
    var ssdTemp: Double?

    var end: Date { start.addingTimeInterval(seconds) }
}

struct NameTable {
    private var strings: Set<String> = []

    mutating func intern(_ s: String) -> String {
        if let existing = strings.firstIndex(of: s) { return strings[existing] }
        strings.insert(s)
        return s
    }

    mutating func intern(_ b: PowerBucket) -> PowerBucket {
        var b = b
        b.source = b.source.map { intern($0) }
        b.apps = b.apps.map { a in
            var a = a
            a.name = intern(a.name)
            a.path = a.path.map { intern($0) }
            return a
        }
        return b
    }
}

struct AppUsageReading {
    var energy: [AppStat]
    var cpu: [AppStat]
    var memory: [AppStat]
}

struct PowerAccumulator {
    private static let maxReadingSeconds = 60.0
    private static let extraAppsPerKind = 6

    let start: Date
    private var samples = 0
    private var cpu = 0.0, gpu = 0.0, memory = 0.0, pressure = 0.0, netUp = 0.0, netDown = 0.0
    private var socSum = 0.0, socCount = 0, socMax: Double?
    private var batTempSum = 0.0, batTempCount = 0, ssdSum = 0.0, ssdCount = 0
    private var fanSum = 0.0, fanCount = 0
    private var battery: Int?, source: String?
    private var powerSeconds = 0.0, systemJoules = 0.0, systemSeconds = 0.0
    private var apps: [String: AppEnergy] = [:]

    init(start: Date) { self.start = start }

    var isEmpty: Bool { samples == 0 && powerSeconds == 0 }
    var seconds: Double { isEmpty ? 0 : max(powerSeconds, 1) }

    mutating func add(_ s: Sample) {
        samples += 1
        cpu += s.load.total
        gpu += s.gpu ?? 0
        memory += s.memory.total > 0 ? s.memory.used / s.memory.total : 0
        pressure += Double(s.pressure)
        netUp += s.net.up
        netDown += s.net.down
        if let t = s.temps.soc {
            socSum += t; socCount += 1
            socMax = max(socMax ?? t, t)
        }
        if let t = s.temps.battery { batTempSum += t; batTempCount += 1 }
        if let t = s.temps.ssd { ssdSum += t; ssdCount += 1 }
        if let rpm = FanMonitor.average(s.fans) { fanSum += rpm; fanCount += 1 }
        if let b = s.battery { battery = b.percent; source = b.state }
    }

    mutating func add(system: Double?, apps reading: AppUsageReading, interval: Double) {
        let seconds = min(interval, Self.maxReadingSeconds)
        powerSeconds += seconds
        if let w = system { systemJoules += w * seconds; systemSeconds += seconds }
        func update(_ a: AppStat, _ change: (inout AppEnergy) -> Void) {
            let key = a.path ?? a.name
            var e = apps[key] ?? AppEnergy(name: a.name, path: a.path, joules: 0)
            change(&e)
            apps[key] = e
        }
        for a in reading.energy { update(a) { $0.joules += a.value * interval } }
        for a in reading.cpu { update(a) { $0.cpuSeconds = ($0.cpuSeconds ?? 0) + a.value * interval } }
        for a in reading.memory { update(a) { $0.peakMemory = max($0.peakMemory ?? 0, a.value) } }
    }

    func bucket(appLimit: Int) -> PowerBucket? {
        guard !isEmpty else { return nil }
        let n = Double(max(samples, 1))
        let all = Array(apps.values)
        var keep = Set(all.sorted { $0.joules > $1.joules }.prefix(appLimit).map { $0.path ?? $0.name })
        keep.formUnion(all.sorted { ($0.cpuSeconds ?? 0) > ($1.cpuSeconds ?? 0) }.prefix(Self.extraAppsPerKind).map { $0.path ?? $0.name })
        keep.formUnion(all.sorted { ($0.peakMemory ?? 0) > ($1.peakMemory ?? 0) }.prefix(Self.extraAppsPerKind).map { $0.path ?? $0.name })
        return PowerBucket(
            start: start,
            seconds: max(powerSeconds, 1),
            systemWatts: systemSeconds > 0 ? systemJoules / systemSeconds : nil,
            cpu: cpu / n, gpu: gpu / n, memory: memory / n,
            socTemp: socCount > 0 ? socSum / Double(socCount) : nil, socTempMax: socMax,
            fanRpm: fanCount > 0 ? fanSum / Double(fanCount) : nil,
            battery: battery, source: source,
            apps: all.filter { keep.contains($0.path ?? $0.name) }.sorted { $0.joules > $1.joules },
            netUp: samples > 0 ? netUp / n : nil, netDown: samples > 0 ? netDown / n : nil,
            pressure: samples > 0 ? pressure / n : nil,
            batteryTemp: batTempCount > 0 ? batTempSum / Double(batTempCount) : nil,
            ssdTemp: ssdCount > 0 ? ssdSum / Double(ssdCount) : nil)
    }
}
