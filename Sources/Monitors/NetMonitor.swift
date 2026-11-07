import AppKit

final class NetMonitor {
    private var prev: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    private func totals() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return (0, 0) }
        defer { freeifaddrs(head) }
        var p = head
        while let ifa = p?.pointee {
            defer { p = ifa.ifa_next }
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data, String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
        }
        return (rx, tx)
    }

    private(set) var totalUp: Double = 0, totalDown: Double = 0

    func rate() -> (up: Double, down: Double) {
        let now = ProcessInfo.processInfo.systemUptime, t = totals()
        defer { prev = (t.rx, t.tx, now) }
        guard let p = prev, now > p.time else { return (0, 0) }
        let dt = now - p.time
        let down = t.rx >= p.rx ? Double(t.rx - p.rx) / dt : 0
        let up = t.tx >= p.tx ? Double(t.tx - p.tx) / dt : 0
        totalDown += down * dt; totalUp += up * dt
        return (up, down)
    }

    static func format(_ bps: Double, compact: Bool = false) -> String {
        let units = compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = bps, i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1024; i += 1 }
        let num = (i == 0 || v >= 100) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return compact ? num + units[i] : num + " " + units[i]
    }
}
