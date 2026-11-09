import Foundation

struct EnergyShare: Identifiable {
    var name: String
    var path: String?
    var joules: Double
    var id: String { name }
}

struct TrendPoint: Identifiable {
    var time: Date
    var watts: Double
    var cpu: Double
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

    static func shares(_ buckets: [PowerBucket], limit: Int) -> [EnergyShare] {
        var totals: [String: EnergyShare] = [:]
        for b in buckets {
            for a in b.apps {
                var s = totals[a.name] ?? EnergyShare(name: a.name, path: a.path, joules: 0)
                s.joules += a.joules
                totals[a.name] = s
            }
        }
        let sorted = totals.values.filter { $0.joules > 0 }.sorted { $0.joules > $1.joules }
        var top = Array(sorted.prefix(limit))
        let rest = sorted.dropFirst(limit).reduce(0) { $0 + $1.joules }
        if rest > 0 { top.append(EnergyShare(name: otherName, path: nil, joules: rest)) }
        return top
    }

    static func hourlyTrend(_ buckets: [PowerBucket]) -> [TrendPoint] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: buckets) { cal.dateInterval(of: .hour, for: $0.start)?.start ?? $0.start }
        return groups.keys.sorted().compactMap { hour in
            guard let list = groups[hour] else { return nil }
            let powered = list.filter { $0.systemWatts != nil }
            let pw = powered.reduce(0) { $0 + $1.seconds }, all = list.reduce(0) { $0 + $1.seconds }
            guard pw > 0, all > 0 else { return nil }
            return TrendPoint(time: hour, watts: powered.reduce(0) { $0 + ($1.systemWatts ?? 0) * $1.seconds } / pw,
                              cpu: list.reduce(0) { $0 + $1.cpu * $1.seconds } / all)
        }
    }

    static func daily(_ buckets: [PowerBucket]) -> [DailyEnergy] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: buckets) { cal.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { day in
            DailyEnergy(day: day, wattHours: (groups[day] ?? []).reduce(0) { $0 + ($1.systemWatts ?? 0) * $1.seconds } / secondsPerHour)
        }
    }
}
