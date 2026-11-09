import Foundation

enum PowerReport {
    private static let secondsPerHour = 3600.0
    private static let topAppCount = 20
    private static let hourlyAppCount = 3
    private static let bytesPerMB = 1_048_576.0

    static var systemPrompt: String {
        let language = Lang.isZh ? "Write every text value in Simplified Chinese." : "Write every text value in English."
        return """
        You analyze power and performance data recorded on a Mac by MenuRunner, a menu bar system monitor. \
        The user wants to understand how their Mac is used and behaves: what drains power, what keeps the CPU and GPU busy, \
        memory pressure, temperatures and fans, battery use and network activity, and what they can change. \
        Ground every claim in the numbers you are given and say when the data is too thin to conclude something. \
        Cover: which apps use the most energy, CPU and memory and whether that looks expected for what they are; \
        patterns over time such as time of day, idle periods with high draw, battery versus AC; \
        how power relates to CPU, GPU, temperature and fan speed; memory pressure; network use; anything that looks abnormal; \
        and a short list of concrete, practical suggestions ordered by expected impact. \
        Per-app figures come from the kernel's per-process energy counters, so they are estimates that do not add up to the whole-system figure. \
        \(language)

        """ + AnalysisResult.schemaPrompt
    }

    static func build(_ buckets: [PowerBucket], spec: MachineSpec) -> String {
        guard let first = buckets.first, let last = buckets.last else { return "" }
        let recorded = buckets.reduce(0) { $0 + $1.seconds }
        var lines: [String] = []
        lines.append("# Machine")
        lines.append("\(spec.model), \(spec.chip), \(spec.pCores)P+\(spec.eCores)E CPU cores, \(spec.gpuCores) GPU cores, \(spec.memoryGB) GB memory, \(spec.os)")
        lines.append("")
        lines.append("# Period")
        lines.append("From \(stamp(first.start)) to \(stamp(last.end)) local time, \(hours(recorded)) hours actually recorded (gaps are sleep or app not running).")
        lines.append("")
        lines.append(contentsOf: overview(buckets, recorded: recorded))
        lines.append("")
        lines.append(contentsOf: topApps(buckets, recorded: recorded))
        lines.append("")
        lines.append(contentsOf: hourly(buckets))
        return lines.joined(separator: "\n")
    }

    private static func overview(_ buckets: [PowerBucket], recorded: Double) -> [String] {
        let powered = buckets.filter { $0.systemWatts != nil }
        let poweredSeconds = powered.reduce(0) { $0 + $1.seconds }
        let joules = powered.reduce(0) { $0 + ($1.systemWatts ?? 0) * $1.seconds }
        let onBattery = buckets.filter { $0.source == "battery" }.reduce(0) { $0 + $1.seconds }
        let peak = buckets.compactMap(\.systemWatts).max()
        let maxTemp = buckets.compactMap(\.socTempMax).max()
        func avg(_ k: KeyPath<PowerBucket, Double>) -> Double { recorded > 0 ? buckets.reduce(0) { $0 + $1[keyPath: k] * $1.seconds } / recorded : 0 }
        var out = ["# Overview"]
        if poweredSeconds > 0 {
            out.append(String(format: "Whole-system power: average %.1f W, peak 5-minute average %.1f W, total %.1f Wh", joules / poweredSeconds, peak ?? 0, joules / secondsPerHour))
        } else {
            out.append("Whole-system power: not available on this Mac")
        }
        out.append(String(format: "Average CPU %.0f%%, GPU %.0f%%, memory used %.0f%%", avg(\.cpu) * 100, avg(\.gpu) * 100, avg(\.memory) * 100))
        if let maxTemp { out.append(String(format: "Highest SoC temperature %.0f °C", maxTemp)) }
        if let t = PowerStats.average(buckets, metric: .batteryTemp) { out.append(String(format: "Highest battery temperature %.1f °C", t)) }
        if let t = buckets.compactMap(\.ssdTemp).max() { out.append(String(format: "Highest SSD temperature %.0f °C", t)) }
        if let p = PowerStats.average(buckets, metric: .pressure) {
            let elevated = buckets.filter { ($0.pressure ?? 0) >= 1.5 }.reduce(0) { $0 + $1.seconds }
            out.append(String(format: "Memory pressure level average %.2f (1 normal, 2 warning, 4 critical), elevated for %.0f%% of recorded time", p, recorded > 0 ? elevated / recorded * 100 : 0))
        }
        if let fan = PowerStats.average(buckets, metric: .fan) {
            out.append(String(format: "Fan average %.0f RPM, max 5-minute average %.0f RPM", fan, buckets.compactMap(\.fanRpm).max() ?? 0))
        }
        let down = buckets.reduce(0) { $0 + ($1.netDown ?? 0) * $1.seconds }, up = buckets.reduce(0) { $0 + ($1.netUp ?? 0) * $1.seconds }
        if down + up > 0 { out.append(String(format: "Network transferred: %.0f MB down, %.0f MB up", down / bytesPerMB, up / bytesPerMB)) }
        if recorded > 0 { out.append(String(format: "Time on battery: %.0f%% of recorded time", onBattery / recorded * 100)) }
        return out
    }

    private static func topApps(_ buckets: [PowerBucket], recorded: Double) -> [String] {
        var totals: [String: (joules: Double, cpu: Double, memory: Double, active: Double)] = [:]
        for b in buckets {
            for a in b.apps {
                var t = totals[a.name] ?? (0, 0, 0, 0)
                t.joules += a.joules
                t.cpu += a.cpuSeconds ?? 0
                t.memory = max(t.memory, a.peakMemory ?? 0)
                t.active += b.seconds
                totals[a.name] = t
            }
        }
        let all = totals.values.reduce(0) { $0 + $1.joules }
        let hasCPU = buckets.contains { $0.apps.contains { $0.cpuSeconds != nil } }
        let hasMemory = buckets.contains { $0.apps.contains { $0.peakMemory != nil } }
        var out = ["# Apps (name, energy Wh, average W over recorded time, share of per-app energy, average CPU as % of one core, peak memory MB, hours seen)"]
        let byEnergy = totals.sorted { $0.value.joules > $1.value.joules }.prefix(topAppCount).map(\.key)
        let byCPU = totals.sorted { $0.value.cpu > $1.value.cpu }.prefix(hourlyAppCount * 2).map(\.key)
        let byMemory = totals.sorted { $0.value.memory > $1.value.memory }.prefix(hourlyAppCount * 2).map(\.key)
        var seen = Set<String>()
        for name in byEnergy + byCPU + byMemory where seen.insert(name).inserted {
            guard let t = totals[name] else { continue }
            let cpu = hasCPU && recorded > 0 ? String(format: "%.0f%%", t.cpu / recorded * 100) : "-"
            let memory = hasMemory ? String(format: "%.0f MB", t.memory / bytesPerMB) : "-"
            out.append(String(format: "%@, %.2f Wh, %.2f W, %.0f%%, %@, %@, %.1f h", name, t.joules / secondsPerHour,
                              recorded > 0 ? t.joules / recorded : 0, all > 0 ? t.joules / all * 100 : 0, cpu, memory, t.active / secondsPerHour))
        }
        return out
    }

    private static func hourly(_ buckets: [PowerBucket]) -> [String] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: buckets) { cal.dateInterval(of: .hour, for: $0.start)?.start ?? $0.start }
        var out = ["# Hourly (hour, recorded min, system W, CPU %, GPU %, memory %, memory pressure, SoC °C avg/max, battery °C, fan RPM, download KB/s, upload KB/s, battery %, power source, top apps W)"]
        for hour in groups.keys.sorted() {
            guard let list = groups[hour] else { continue }
            let secs = list.reduce(0) { $0 + $1.seconds }
            guard secs > 0 else { continue }
            func avg(_ v: (PowerBucket) -> Double?) -> String {
                let pairs = list.compactMap { b in v(b).map { ($0, b.seconds) } }
                let w = pairs.reduce(0) { $0 + $1.1 }
                return w > 0 ? String(format: "%.1f", pairs.reduce(0) { $0 + $1.0 * $1.1 } / w) : "-"
            }
            var apps: [String: Double] = [:]
            for b in list { for a in b.apps { apps[a.name, default: 0] += a.joules } }
            let top = apps.sorted { $0.value > $1.value }.prefix(hourlyAppCount)
                .map { String(format: "%@ %.2f", $0.key, $0.value / secs) }.joined(separator: "; ")
            let source = list.last?.source ?? "-"
            let battery = list.last?.battery.map(String.init) ?? "-"
            let temps = avg { $0.socTemp } + "/" + (list.compactMap(\.socTempMax).max().map { String(format: "%.0f", $0) } ?? "-")
            out.append([stamp(hour), String(format: "%.0f", secs / 60), avg { $0.systemWatts }, avg { $0.cpu * 100 }, avg { $0.gpu * 100 },
                        avg { $0.memory * 100 }, avg { $0.pressure }, temps, avg { $0.batteryTemp }, avg { $0.fanRpm },
                        avg { $0.netDown.map { $0 / 1024 } }, avg { $0.netUp.map { $0 / 1024 } }, battery, source, top].joined(separator: ", "))
        }
        return out
    }

    private static func hours(_ seconds: Double) -> String { String(format: "%.1f", seconds / secondsPerHour) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEE HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func stamp(_ d: Date) -> String { formatter.string(from: d) }
}
