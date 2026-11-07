import AppKit
import QuartzCore

struct Sample {
    var load = CPULoad(), gpu: Double?, memory = SystemInfo.Memory(), net: (up: Double, down: Double) = (0, 0)
    var temps = Temps(), battery: (percent: Int, state: String)?, health: BatteryHealth?
    var storage: (used: Double, total: Double)?, batteryTime: (label: String, value: String)?, pressure = 1
    var gpuMemory: Double?, netTotals: (up: Double, down: Double) = (0, 0), fans: [Fan] = []
}

final class Sampler {
    private let cpu = CPUMonitor()
    private let netMon = NetMonitor()
    private var lastTemps: Temps?
    private var lastTempsAt: CFTimeInterval = 0

    func prime() { _ = cpu.load(); _ = netMon.rate() }

    func collect(needTemps: Bool, needFans: Bool, panelVisible: Bool) -> Sample {
        var s = Sample()
        s.load = cpu.load()
        if lastTemps == nil || (needTemps && CACurrentMediaTime() - lastTempsAt >= 2) {
            lastTemps = TempMonitor.shared.read(); lastTempsAt = CACurrentMediaTime()
        }
        s.temps = lastTemps ?? Temps()
        s.gpu = GPUMonitor.usage(); s.memory = SystemInfo.memory(); s.net = netMon.rate()
        s.battery = SystemInfo.battery(); s.health = SystemInfo.batteryHealth(); s.storage = SystemInfo.storage()
        s.batteryTime = SystemInfo.batteryTime(); s.pressure = SystemInfo.memoryPressure()
        if panelVisible { s.gpuMemory = GPUMonitor.memoryInUse() }
        s.netTotals = (netMon.totalUp, netMon.totalDown)
        if needFans { s.fans = FanMonitor.shared.read() }
        return s
    }
}
