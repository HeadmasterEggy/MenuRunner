import Foundation

final class PowerRecorder {
    static let shared = PowerRecorder()
    static let bucketSeconds: TimeInterval = 300
    static let retention: TimeInterval = 14 * 86400
    private static let idleInterval: TimeInterval = 10
    private static let activeInterval: TimeInterval = 2
    private static let appsPerBucket = 12
    private static let appsPerReading = 40
    private static let liveLimit = 8
    private static let enabledKey = "powerRecording"

    private(set) var buckets: [PowerBucket] = []
    private(set) var liveApps: [AppStat] = []
    private(set) var liveSystem: Double?
    var onUpdate: () -> Void = {}

    private let monitor = PowerMonitor()
    private var current = PowerAccumulator(start: Date())
    private var timer: Timer?
    private var active = false
    private var reading = false
    private var names = NameTable()
    private let saveQueue = DispatchQueue(label: "menurunner.power.save", qos: .utility)

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MenuRunner/power-history.json")
    }()

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { commit() }
            reschedule()
        }
    }

    var liveWatts: Double? { liveSystem ?? (liveApps.isEmpty ? nil : liveApps.reduce(0) { $0 + $1.value }) }

    func start() {
        load()
        reschedule()
        sampleNow()
    }

    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        reschedule()
        if on { sampleNow() }
    }

    func flush() {
        commit()
        current = PowerAccumulator(start: Date())
    }

    func ingest(_ s: Sample) {
        guard enabled else { return }
        rollIfNeeded()
        current.add(s)
    }

    func sampleNow() {
        guard !reading else { return }
        reading = true
        let monitor = self.monitor
        sampleQueue.async { [weak self] in
            let r = monitor.read()
            let grouped = r.map {
                AppUsageReading(energy: AppIdentity.group($0.perPid, limit: Self.appsPerReading),
                                cpu: AppIdentity.group($0.cpuPerPid, limit: Self.appsPerReading),
                                memory: AppIdentity.group($0.memoryPerPid, limit: Self.appsPerReading))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                if let r, let grouped { self.consume(r, grouped: grouped) }
            }
        }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard enabled || active else { return }
        let t = Timer(timeInterval: active ? Self.activeInterval : Self.idleInterval, repeats: true) { [weak self] _ in self?.sampleNow() }
        t.tolerance = active ? 0.2 : 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func consume(_ r: PowerReading, grouped: AppUsageReading) {
        liveSystem = r.system
        liveApps = Array(grouped.energy.prefix(Self.liveLimit))
        if enabled {
            rollIfNeeded()
            current.add(system: r.system, apps: grouped, interval: r.interval)
        }
        onUpdate()
    }

    private func rollIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(current.start) >= Self.bucketSeconds else { return }
        commit()
        current = PowerAccumulator(start: now)
    }

    private func commit() {
        guard let b = current.bucket(appLimit: Self.appsPerBucket) else { return }
        current = PowerAccumulator(start: Date())
        buckets.append(names.intern(b))
        let cutoff = Date().addingTimeInterval(-Self.retention)
        buckets.removeAll { $0.start < cutoff }
        save()
    }

    private func save() {
        let snapshot = buckets, url = fileURL
        saveQueue.async {
            autoreleasepool {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func waitForSave() { saveQueue.sync {} }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe), let saved = try? JSONDecoder().decode([PowerBucket].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        buckets = saved.filter { $0.start >= cutoff }.map { names.intern($0) }
    }

    private func window(hours: Double) -> ArraySlice<PowerBucket> {
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        var lo = buckets.startIndex, hi = buckets.endIndex
        while lo < hi {
            let mid = (lo + hi) / 2
            if buckets[mid].end >= cutoff { hi = mid } else { lo = mid + 1 }
        }
        return buckets[lo...]
    }

    private func forEachRecent(hours: Double, appLimit: Int = PowerRecorder.appsPerBucket, _ body: (PowerBucket) -> Void) {
        window(hours: hours).forEach(body)
        if let partial = current.bucket(appLimit: appLimit) { body(partial) }
    }

    func recent(hours: Double) -> [PowerBucket] {
        var list = Array(window(hours: hours))
        if let partial = current.bucket(appLimit: Self.appsPerReading) { list.append(partial) }
        return list
    }

    func recordedSeconds(hours: Double) -> Double {
        window(hours: hours).reduce(current.seconds) { $0 + $1.seconds }
    }

    func topApps(hours: Double, limit: Int) -> [AppStat] {
        var totals: [String: AppStat] = [:]
        forEachRecent(hours: hours, appLimit: Self.appsPerReading) { b in
            for a in b.apps {
                let key = a.path ?? a.name
                var s = totals[key] ?? AppStat(name: a.name, path: a.path, value: 0, processes: 1)
                s.value += a.joules
                totals[key] = s
            }
        }
        return Array(totals.values.sorted { $0.value > $1.value }.prefix(limit))
    }

    func systemEnergy(hours: Double) -> Double {
        var total = 0.0
        forEachRecent(hours: hours) { total += ($0.systemWatts ?? 0) * $0.seconds }
        return total
    }

    func averageWatts(hours: Double) -> Double? {
        var joules = 0.0, seconds = 0.0
        forEachRecent(hours: hours) { b in
            guard let w = b.systemWatts else { return }
            joules += w * b.seconds
            seconds += b.seconds
        }
        return seconds > 0 ? joules / seconds : nil
    }

    func hourlyWatts(hours: Int) -> [Double?] {
        let now = Date()
        var sums = [Double](repeating: 0, count: hours), weights = [Double](repeating: 0, count: hours)
        forEachRecent(hours: Double(hours)) { b in
            guard let w = b.systemWatts else { return }
            let age = Int(now.timeIntervalSince(b.start) / 3600)
            guard age >= 0, age < hours else { return }
            let i = hours - 1 - age
            sums[i] += w * b.seconds
            weights[i] += b.seconds
        }
        return zip(sums, weights).map { $1 > 0 ? $0 / $1 : nil }
    }
}
