import AppKit
import QuartzCore

final class StatsModel {
    static var interval = 1.5
    static let historyLength = 120

    var cpu = CPULoad(), gpu: Double?, memory = SystemInfo.Memory()
    var storage: (used: Double, total: Double)?
    var battery: (percent: Int, state: String)?, health: BatteryHealth?
    var temps = Temps(), net: (up: Double, down: Double) = (0, 0)
    var cpuHistory: [CPULoad] = [], gpuHistory: [Double] = [], netHistory: [(up: Double, down: Double)] = []
    var memHistory: [Double] = [], fanHistory: [Double] = []
    var fans: [Fan] = []
    var lastSample = CACurrentMediaTime()

    private var target: [String: Double] = [:]
    private var shown: [String: Double] = [:]

    func set(_ k: String, _ v: Double) { target[k] = v; if shown[k] == nil { shown[k] = v } }
    func v(_ k: String) -> Double { shown[k] ?? 0 }
    func resetShown() { for k in target.keys { shown[k] = 0 } }

    func tick(dt: Double) {
        let a = 1 - exp(-dt * 7)
        for (k, t) in target { let s = shown[k] ?? t; shown[k] = s + (t - s) * a }
    }

    var scroll: Double { min((CACurrentMediaTime() - lastSample) / Self.interval, 1) }

    func update(cpu: CPULoad, gpu: Double?, memory: SystemInfo.Memory, storage: (used: Double, total: Double)?,
                battery: (percent: Int, state: String)?, health: BatteryHealth?, temps: Temps, net: (up: Double, down: Double), fans: [Fan] = []) {
        self.cpu = cpu; self.gpu = gpu; self.memory = memory; self.storage = storage
        self.battery = battery; self.health = health; self.temps = temps; self.net = net; self.fans = fans
        func push<T>(_ a: inout [T], _ x: T) { a.append(x); if a.count > Self.historyLength { a.removeFirst() } }
        if cpuHistory.isEmpty {
            cpuHistory = Array(repeating: cpu, count: Self.historyLength)
            gpuHistory = Array(repeating: gpu ?? 0, count: Self.historyLength)
            netHistory = Array(repeating: net, count: Self.historyLength)
            memHistory = Array(repeating: memory.used / memory.total, count: Self.historyLength)
            fanHistory = Array(repeating: FanMonitor.peakFraction(fans), count: Self.historyLength)
        }
        push(&memHistory, memory.used / memory.total)
        push(&fanHistory, FanMonitor.peakFraction(fans))
        push(&cpuHistory, cpu); push(&gpuHistory, gpu ?? 0); push(&netHistory, net)
        lastSample = CACurrentMediaTime()

        set("cpu", cpu.total); set("sys", cpu.system); set("user", cpu.user); set("idle", cpu.idle)
        set("gpu", gpu ?? 0)
        set("mem", memory.used / memory.total); set("memUsed", memory.used)
        set("app", memory.app / memory.total); set("wired", memory.wired / memory.total); set("comp", memory.compressed / memory.total)
        if let s = storage { set("disk", s.used / s.total) }
        if let b = battery { set("bat", Double(b.percent) / 100) }
        if let h = health { set("health", h.health) }
        if let t = temps.soc { set("tSoc", t) }
        if let t = temps.battery { set("tBat", t) }
        if let t = temps.ssd { set("tSsd", t) }
        set("up", net.up); set("down", net.down)
        if let rpm = FanMonitor.average(fans) { set("fan", rpm); set("fanFrac", FanMonitor.peakFraction(fans)) }
        for f in fans { set("fan\(f.index)", f.rpm) }
    }
}
