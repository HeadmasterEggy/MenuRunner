import AppKit

struct CPULoad { var user = 0.0, system = 0.0, idle = 1.0; var total: Double { user + system } }

final class CPUMonitor {
    private var prev: host_cpu_load_info?

    func load() -> CPULoad {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return CPULoad() }
        defer { prev = info }
        guard let p = prev else { return CPULoad() }
        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let sys  = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + sys + idle + nice
        guard total > 0 else { return CPULoad() }
        return CPULoad(user: (user + nice) / total, system: sys / total, idle: idle / total)
    }
}
