import AppKit
import QuartzCore
import IOKit
import SystemConfiguration

struct AppStat { var name: String, path: String?, value: Double, processes: Int }
struct NetInterface { var bsd: String, name: String, ipv4: String, up: Double, down: Double }
struct ProcMem { var pid: pid_t, name: String, path: String?, bytes: UInt64, user: String }
struct VolumeInfo { var name: String, path: String, used: Double, total: Double }

enum DetailKind { case system, cpu, gpu, memory, temps, storage, battery, network, power }

enum AppIdentity {
    private static var cache: [pid_t: (key: String, name: String, path: String?)] = [:]
    private static let lock = NSRecursiveLock()

    static func of(_ pid: pid_t) -> (key: String, name: String, path: String?) {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[pid] { return c }
        let v = lookup(pid); cache[pid] = v; return v
    }

    static func prune(_ alive: [pid_t]) {
        let set = Set(alive)
        lock.lock(); defer { lock.unlock() }
        cache = cache.filter { set.contains($0.key) }
        procCache = procCache.filter { set.contains($0.key) }
    }

    private static var procCache: [pid_t: (name: String, path: String?)] = [:]
    static func process(_ pid: pid_t) -> (name: String, path: String?) {
        lock.lock(); defer { lock.unlock() }
        if let c = procCache[pid] { return c }
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = len > 0 ? String(cString: buf) : ""
        var name = (path as NSString).lastPathComponent
        if name.isEmpty { var nb = [CChar](repeating: 0, count: 256); proc_name(pid, &nb, UInt32(nb.count)); name = String(cString: nb) }
        if name.isEmpty { name = "pid \(pid)" }
        let v = (name, of(pid).path ?? (path.isEmpty ? nil : path))
        procCache[pid] = v; return v
    }

    private static func lookup(_ pid: pid_t) -> (key: String, name: String, path: String?) {
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = len > 0 ? String(cString: buf) : ""
        if let r = path.range(of: ".app/") {
            let app = String(path[..<r.lowerBound]) + ".app"
            return (app, (app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""), app)
        }
        var name = (path as NSString).lastPathComponent
        if name.isEmpty {
            var nb = [CChar](repeating: 0, count: 256); proc_name(pid, &nb, UInt32(nb.count)); name = String(cString: nb)
        }
        return (path.isEmpty ? name : path, name, nil)
    }

    static func group(_ perPid: [pid_t: Double], limit: Int) -> [AppStat] {
        var g: [String: AppStat] = [:]
        for (pid, v) in perPid where v > 0 {
            let id = of(pid)
            var a = g[id.key] ?? AppStat(name: id.name, path: id.path, value: 0, processes: 0)
            a.value += v; a.processes += 1
            g[id.key] = a
        }
        return Array(g.values.sorted { $0.value > $1.value }.prefix(limit))
    }

    static func allPids() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let got = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let alive = pids.prefix(Int(max(got, 0))).filter { $0 > 0 }
        prune(alive)
        return alive
    }
}

let sampleQueue = DispatchQueue(label: "menurunner.sample", qos: .userInitiated)

final class DetailProvider {
    var cores: [Double] = []
    var cpuApps: [AppStat] = [], gpuApps: [AppStat] = [], netApps: [AppStat] = []
    var memApps: [AppMemory] = []
    var memProcs: [ProcMem] = []
    var interfaces: [NetInterface] = []
    var volumes: [VolumeInfo] = []
    var sensors: [(String, Double)] = []
    var gpuStats: [String: Int] = [:]
    var sampled = false

    private var prevCores: [Int32]?
    private var prevCPU: [pid_t: UInt64] = [:], prevGPU: [pid_t: UInt64] = [:]
    private var prevIf: [String: (UInt64, UInt64)] = [:]
    private let timebase: Double = { var tb = mach_timebase_info(); mach_timebase_info(&tb); return Double(tb.numer) / Double(tb.denom) }()
    private lazy var ifNames: [String: String] = {
        var map: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let b = SCNetworkInterfaceGetBSDName(i) as String?, let n = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? { map[b] = n }
        }
        return map
    }()

    var onUpdate: () -> Void = {}

    func reset() { stopNetwork(); sampled = false }

    private var tCPU: CFTimeInterval = 0, tGPU: CFTimeInterval = 0, tIf: CFTimeInterval = 0
    private func dt(_ t: inout CFTimeInterval) -> Double {
        let now = CACurrentMediaTime(); defer { t = now }
        return max(now - t, 0.001)
    }

    func prime() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let c = self.collectCores(), a = self.collectCPUApps(self.dt(&self.tCPU))
            let g = self.collectGPU(self.dt(&self.tGPU)), i = self.collectInterfaces(self.dt(&self.tIf))
            self.publish {
                if let c { self.cores = c }
                if let a { self.cpuApps = a }
                self.applyGPU(g)
                if let i { self.interfaces = i }
            }
        }
    }

    func prewarmStorage() { refreshAppSizes() }

    func refresh(_ kind: DetailKind, wait: Bool = false) {
        switch kind {
        case .memory:  startMemTop()
        case .storage: refreshAppSizes()
        case .network: refreshNetApps()
        default: break
        }
        sampled = true
        if wait {
            var apply: () -> Void = {}
            sampleQueue.sync { apply = self.collect(kind) }
            apply()
        } else {
            sampleQueue.async { [weak self] in
                guard let self else { return }
                self.publish(self.collect(kind))
            }
        }
    }

    private func publish(_ apply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in apply(); self?.onUpdate() }
    }

    private func collect(_ kind: DetailKind) -> () -> Void {
        switch kind {
        case .cpu:
            let c = collectCores(), a = collectCPUApps(dt(&tCPU))
            return { [weak self] in if let c { self?.cores = c }; if let a { self?.cpuApps = a } }
        case .gpu:
            let g = collectGPU(dt(&tGPU))
            return { [weak self] in self?.applyGPU(g) }
        case .memory:
            let m = ProcessMemory.top(PanelController.procRows)
            return { [weak self] in self?.memApps = m }
        case .temps:
            let t = TempMonitor.shared.readAll()
            return { [weak self] in self?.sensors = t }
        case .storage:
            let v = collectVolumes()
            return { [weak self] in self?.volumes = v }
        case .network:
            let i = collectInterfaces(dt(&tIf))
            return { [weak self] in if let i { self?.interfaces = i } }
        default:
            return {}
        }
    }

    private func applyGPU(_ g: (apps: [AppStat]?, stats: [String: Int])) {
        for (k, v) in g.stats { gpuStats[k] = v }
        if let a = g.apps { gpuApps = a }
    }

    private func collectCores() -> [Double]? {
        var n: natural_t = 0, info: processor_info_array_t?, count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) == KERN_SUCCESS, let info else { return nil }
        let arr = Array(UnsafeBufferPointer(start: info, count: Int(count)))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        defer { prevCores = arr }
        if let p = prevCores, p.count == arr.count {
            return (0..<Int(n)).map { i in
                let b = i * Int(CPU_STATE_MAX)
                func d(_ k: Int32) -> Double { Double(arr[b + Int(k)] &- p[b + Int(k)]) }
                let busy = d(CPU_STATE_USER) + d(CPU_STATE_SYSTEM) + d(CPU_STATE_NICE), total = busy + d(CPU_STATE_IDLE)
                return total > 0 ? busy / total : 0
            }
        }
        return nil
    }

    private func collectCPUApps(_ dt: Double) -> [AppStat]? {
        var cur: [pid_t: UInt64] = [:], rate: [pid_t: Double] = [:]
        for pid in AppIdentity.allPids() {
            var u = rusage_info_current()
            let r = withUnsafeMutablePointer(to: &u) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) } }
            guard r == 0 else { continue }
            let t = u.ri_user_time + u.ri_system_time
            cur[pid] = t
            if let p = prevCPU[pid], t >= p { rate[pid] = Double(t - p) * timebase / (dt * 1e9) }
        }
        defer { prevCPU = cur }
        return prevCPU.isEmpty ? nil : AppIdentity.group(rate, limit: 8)
    }

    private func collectGPU(_ dt: Double) -> (apps: [AppStat]?, stats: [String: Int]) {
        var gpuStats: [String: Int] = [:]
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return (nil, [:]) }
        defer { IOObjectRelease(iter) }
        var cur: [pid_t: UInt64] = [:]
        var accel = IOIteratorNext(iter)
        while accel != 0 {
            if let st = IORegistryEntryCreateCFProperty(accel, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                for k in ["Device Utilization %", "Renderer Utilization %", "Tiler Utilization %", "In use system memory", "Alloc system memory"] {
                    guard let v = st[k] as? Int else { continue }
                    gpuStats[k] = k.hasSuffix("%") ? max(gpuStats[k] ?? 0, v) : (gpuStats[k] ?? 0) + v
                }
            }
            var it: io_iterator_t = 0
            if IORegistryEntryCreateIterator(accel, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &it) == KERN_SUCCESS {
                var c = IOIteratorNext(it)
                while c != 0 {
                    if let creator = IORegistryEntryCreateCFProperty(c, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                       let usage = IORegistryEntryCreateCFProperty(c, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]],
                       let pidStr = creator.split(separator: ",").first?.split(separator: " ").last, let pid = pid_t(pidStr) {
                        let t = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
                        cur[pid, default: 0] += t
                    }
                    IOObjectRelease(c); c = IOIteratorNext(it)
                }
                IOObjectRelease(it)
            }
            IOObjectRelease(accel); accel = IOIteratorNext(iter)
        }
        var rate: [pid_t: Double] = [:]
        for (pid, t) in cur { if let p = prevGPU[pid], t >= p { rate[pid] = Double(t - p) / (dt * 1e9) } }
        defer { prevGPU = cur }
        return (prevGPU.isEmpty ? nil : AppIdentity.group(rate, limit: 8), gpuStats)
    }

    private func collectInterfaces(_ dt: Double) -> [NetInterface]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var ips: [String: String] = [:]
        let bytes = InterfaceCounters.read().mapValues { ($0.rx, $0.tx) }
        var p = head
        while let ifa = p?.pointee {
            defer { p = ifa.ifa_next }
            let name = String(cString: ifa.ifa_name)
            guard name != "lo0", let addr = ifa.ifa_addr, (ifa.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                ips[name] = String(cString: host)
            }
        }
        defer { prevIf = bytes }
        return ips.keys.sorted().prefix(3).map { n in
            let b = bytes[n] ?? (0, 0), pb = prevIf[n] ?? b
            return NetInterface(bsd: n, name: ifNames[n] ?? n, ipv4: ips[n] ?? "",
                                up: b.1 >= pb.1 ? Double(b.1 - pb.1) / dt : 0, down: b.0 >= pb.0 ? Double(b.0 - pb.0) / dt : 0)
        }
    }

    private var netProc: Process?
    private var netPipe: Pipe?
    private var netBuffer = ""
    private var netBlock: [pid_t: Double] = [:]
    private var netBlocks = 0

    private func refreshNetApps() {
        guard netProc == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/usr/bin/nettop", "-P", "-d", "-x", "-L", "0", "-s", "1", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        netBuffer = ""; netBlock = [:]; netBlocks = 0
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else {
                h.readabilityHandler = nil
                DispatchQueue.main.async { if let self, self.netProc === p { self.stopNetApps() } }
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consumeNet(text) }
        }
        guard (try? p.run()) != nil else { return }
        netProc = p; netPipe = pipe
    }

    private func consumeNet(_ chunk: String) {
        netBuffer += chunk
        while let nl = netBuffer.firstIndex(where: \.isNewline) {
            let line = netBuffer[..<nl].trimmingCharacters(in: .whitespacesAndNewlines); netBuffer.removeSubrange(...nl)
            if line.hasPrefix(",") {
                if netBlocks >= 2 {
                    netApps = AppIdentity.group(netBlock, limit: 8)
                    if CommandLine.arguments.contains("--open-panel") {
                        NSLog("net debug: block=%d apps=%d top=%@", netBlocks, netApps.count, netApps.first.map { "\($0.name) \(NetMonitor.format($0.value))" } ?? "-")
                    }
                }
                netBlock = [:]; netBlocks += 1
                continue
            }
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 3, let i = Double(f[1]), let o = Double(f[2]),
                  let pid = pid_t(f[0].split(separator: ".").last ?? "") else { continue }
            netBlock[pid, default: 0] += i + o
        }
    }

    func stopNetwork() {
        stopNetApps()
        stopMemTop()
    }

    private func stopNetApps() {
        netPipe?.fileHandleForReading.readabilityHandler = nil
        netProc?.terminate(); netProc = nil; netPipe = nil
        netApps = []
    }

    private var topProc: Process?
    private var topPipe: Pipe?
    private var topBuffer = ""
    private var topBlock: [ProcMem] = []

    private func startMemTop() {
        guard topProc == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        p.arguments = ["-q", "/dev/null", "/usr/bin/top", "-l", "0", "-s", "3", "-o", "mem", "-n", "\(PanelController.topProcRows)", "-stats", "pid,mem,user"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        topBuffer = ""; topBlock = []
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else {
                h.readabilityHandler = nil
                DispatchQueue.main.async { if let self, self.topProc === p { self.stopMemTop() } }
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consumeTop(text) }
        }
        guard (try? p.run()) != nil else { return }
        topProc = p; topPipe = pipe
    }

    private func consumeTop(_ chunk: String) {
        topBuffer += chunk
        while let nl = topBuffer.firstIndex(where: \.isNewline) {
            let line = topBuffer[..<nl].trimmingCharacters(in: .whitespacesAndNewlines); topBuffer.removeSubrange(...nl)
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            if f.first == "PID" { topBlock = []; continue }
            guard f.count >= 3, let pid = pid_t(f[0]), let bytes = Self.topBytes(f[1]) else { continue }
            let id = AppIdentity.process(pid)
            topBlock.append(ProcMem(pid: pid, name: id.name, path: id.path, bytes: bytes, user: String(f[2])))
            if topBlock.count == PanelController.topProcRows { memProcs = topBlock; topBlock = [] }
        }
    }

    private static func topBytes(_ s: Substring) -> UInt64? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let u = t.last, let v = Double(t.dropLast()) else { return nil }
        let m: Double = u == "K" ? 1024 : u == "M" ? 1_048_576 : u == "G" ? 1_073_741_824 : u == "B" ? 1 : 0
        return m > 0 ? UInt64(v * m) : nil
    }

    private func stopMemTop() {
        topPipe?.fileHandleForReading.readabilityHandler = nil
        topProc?.terminate(); topProc = nil; topPipe = nil
        memProcs = []
    }

    var appSizes: [AppStat] = []
    var sizeScanning = false
    private var sizeScanTime: CFTimeInterval = 0

    private func refreshAppSizes() {
        guard !sizeScanning, appSizes.isEmpty || CACurrentMediaTime() - sizeScanTime > 600 else { return }
        sizeScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
            let apps = dirs.flatMap { d in ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".app") }.map { d + "/" + $0 } }
            var result: [AppStat] = []
            if !apps.isEmpty {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                p.qualityOfService = .background
                p.arguments = ["-sk"] + apps
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                if (try? p.run()) != nil {
                    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    p.waitUntilExit()
                    for line in out.split(separator: "\n") {
                        let parts = line.split(separator: "\t", maxSplits: 1)
                        guard parts.count == 2, let kb = Double(parts[0]) else { continue }
                        let path = String(parts[1])
                        result.append(AppStat(name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                                              path: path, value: kb * 1024, processes: 1))
                    }
                }
            }
            result.sort { $0.value > $1.value }
            DispatchQueue.main.async {
                self?.appSizes = Array(result.prefix(12)); self?.sizeScanning = false; self?.sizeScanTime = CACurrentMediaTime()
            }
        }
    }

    private func collectVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let free = v.volumeAvailableCapacityForImportantUsage.map(Double.init) ?? Double(v.volumeAvailableCapacity ?? 0)
            return VolumeInfo(name: v.volumeName ?? u.lastPathComponent, path: u.path, used: Double(total) - free, total: Double(total))
        }.prefix(5).map { $0 }
    }
}
