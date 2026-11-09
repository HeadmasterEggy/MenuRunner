import Foundation

enum Metric: String, CaseIterable, Identifiable {
    case power, cpu, gpu, memory, pressure, socTemp, batteryTemp, fan, battery, netDown, netUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: return L("整机功耗", "Power")
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return L("内存", "Memory")
        case .pressure: return L("内存压力", "Mem pressure")
        case .socTemp: return L("芯片温度", "SoC temp")
        case .batteryTemp: return L("电池温度", "Battery temp")
        case .fan: return L("风扇", "Fan")
        case .battery: return L("电量", "Battery")
        case .netDown: return L("下载", "Download")
        case .netUp: return L("上传", "Upload")
        }
    }

    var icon: String {
        switch self {
        case .power: return "bolt.fill"
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .pressure: return "gauge.with.dots.needle.67percent"
        case .socTemp: return "thermometer.medium"
        case .batteryTemp: return "thermometer.low"
        case .fan: return "fan"
        case .battery: return "battery.75percent"
        case .netDown: return "arrow.down.circle"
        case .netUp: return "arrow.up.circle"
        }
    }

    func value(_ b: PowerBucket) -> Double? {
        switch self {
        case .power: return b.systemWatts
        case .cpu: return b.cpu * 100
        case .gpu: return b.gpu * 100
        case .memory: return b.memory * 100
        case .pressure: return b.pressure
        case .socTemp: return b.socTemp
        case .batteryTemp: return b.batteryTemp
        case .fan: return b.fanRpm
        case .battery: return b.battery.map(Double.init)
        case .netDown: return b.netDown
        case .netUp: return b.netUp
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .power: return PowerMonitor.formatWatts(v)
        case .cpu, .gpu, .memory, .battery: return String(format: "%.0f%%", v)
        case .pressure: return v >= 3 ? L("紧张", "Critical") : (v >= 1.5 ? L("偏高", "Elevated") : L("正常", "Normal"))
        case .socTemp, .batteryTemp: return TempUnit.format(v)
        case .fan: return FanMonitor.format(v)
        case .netDown, .netUp: return NetMonitor.format(v)
        }
    }

    var usesMax: Bool { self == .socTemp || self == .batteryTemp }
}

enum RankKind: String, CaseIterable, Identifiable {
    case energy, cpu, memory
    var id: String { rawValue }
    var title: String { self == .energy ? L("耗电", "Energy") : (self == .cpu ? "CPU" : L("内存", "Memory")) }

    func value(_ a: AppEnergy) -> Double {
        switch self {
        case .energy: return a.joules
        case .cpu: return a.cpuSeconds ?? 0
        case .memory: return a.peakMemory ?? 0
        }
    }

    func format(_ v: Double, seconds: Double) -> String {
        switch self {
        case .energy: return PowerMonitor.formatEnergy(v)
        case .cpu: return String(format: L("%.0f%% 核", "%.0f%% core"), seconds > 0 ? v / seconds * 100 : 0)
        case .memory: return ProcessMemory.format(UInt64(v))
        }
    }
}

struct EnergyShare: Identifiable {
    var name: String
    var path: String?
    var joules: Double
    var id: String { name }
}

struct TrendPoint: Identifiable {
    var time: Date
    var value: Double
    var appValue: Double?
    var id: Date { time }
}

struct DailyEnergy: Identifiable {
    var day: Date
    var wattHours: Double
    var id: Date { day }
}

enum PowerStats {
    private static let secondsPerHour = 3600.0
    static let otherName = "__other__"

    static func step(hours: Int) -> TimeInterval {
        hours <= 24 ? 900 : (hours <= 72 ? 3600 : (hours <= 168 ? 7200 : 14400))
    }

    static func ranking(_ buckets: [PowerBucket], kind: RankKind, limit: Int) -> [EnergyShare] {
        var totals: [String: EnergyShare] = [:]
        for b in buckets {
            for a in b.apps {
                var s = totals[a.name] ?? EnergyShare(name: a.name, path: a.path, joules: 0)
                s.joules = kind == .memory ? max(s.joules, kind.value(a)) : s.joules + kind.value(a)
                totals[a.name] = s
            }
        }
        let sorted = totals.values.filter { $0.joules > 0 }.sorted { $0.joules > $1.joules }
        var top = Array(sorted.prefix(limit))
        let rest = sorted.dropFirst(limit).reduce(0) { $0 + $1.joules }
        if rest > 0, kind != .memory { top.append(EnergyShare(name: otherName, path: nil, joules: rest)) }
        return top
    }

    static func trend(_ buckets: [PowerBucket], metric: Metric, step: TimeInterval, app: String?, cores: Int) -> [TrendPoint] {
        let groups = Dictionary(grouping: buckets) { Date(timeIntervalSince1970: floor($0.start.timeIntervalSince1970 / step) * step) }
        return groups.keys.sorted().compactMap { t in
            guard let list = groups[t] else { return nil }
            let pairs = list.compactMap { b in metric.value(b).map { ($0, b.seconds) } }
            let w = pairs.reduce(0) { $0 + $1.1 }
            guard w > 0 else { return nil }
            let v = metric.usesMax ? (pairs.map(\.0).max() ?? 0) : pairs.reduce(0) { $0 + $1.0 * $1.1 } / w
            return TrendPoint(time: t, value: v, appValue: app.flatMap { appValue(list, app: $0, metric: metric, cores: cores) })
        }
    }

    private static func appValue(_ list: [PowerBucket], app: String, metric: Metric, cores: Int) -> Double? {
        let seconds = list.reduce(0) { $0 + $1.seconds }
        guard seconds > 0 else { return nil }
        let entries = list.flatMap { $0.apps.filter { $0.name == app } }
        switch metric {
        case .power: return entries.reduce(0) { $0 + $1.joules } / seconds
        case .cpu: return entries.reduce(0) { $0 + ($1.cpuSeconds ?? 0) } / seconds / Double(max(cores, 1)) * 100
        case .memory:
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            return (entries.compactMap(\.peakMemory).max() ?? 0) / total * 100
        default: return nil
        }
    }

    static func average(_ buckets: [PowerBucket], metric: Metric) -> Double? {
        let pairs = buckets.compactMap { b in metric.value(b).map { ($0, b.seconds) } }
        let w = pairs.reduce(0) { $0 + $1.1 }
        guard w > 0 else { return nil }
        return metric.usesMax ? pairs.map(\.0).max() : pairs.reduce(0) { $0 + $1.0 * $1.1 } / w
    }

    static func daily(_ buckets: [PowerBucket]) -> [DailyEnergy] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: buckets) { cal.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { day in
            DailyEnergy(day: day, wattHours: (groups[day] ?? []).reduce(0) { $0 + ($1.systemWatts ?? 0) * $1.seconds } / secondsPerHour)
        }
    }
}
