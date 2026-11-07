import AppKit
import IOKit

struct MachineSpec {
    var model = "Mac", chip = "", pCores = 0, eCores = 0, gpuCores = 0
    var memoryGB = 0, diskGB = 0, os = ""

    static func sysctlString(_ k: String) -> String {
        var size = 0
        guard sysctlbyname(k, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(k, &buf, &size, nil, 0)
        return String(cString: buf)
    }
    static func sysctlInt(_ k: String) -> Int {
        var v: Int64 = 0, size = MemoryLayout<Int64>.size
        return sysctlbyname(k, &v, &size, nil, 0) == 0 ? Int(v) : 0
    }

    static func basic() -> MachineSpec {
        var m = MachineSpec()
        m.chip = sysctlString("machdep.cpu.brand_string")
        m.pCores = sysctlInt("hw.perflevel0.physicalcpu")
        m.eCores = sysctlInt("hw.perflevel1.physicalcpu")
        if m.pCores == 0 { m.pCores = sysctlInt("hw.physicalcpu") }
        m.memoryGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let v = ProcessInfo.processInfo.operatingSystemVersion
        m.os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS {
            var e = IOIteratorNext(iter)
            while e != 0 {
                if let n = IORegistryEntryCreateCFProperty(e, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                    m.gpuCores = max(m.gpuCores, n)
                }
                IOObjectRelease(e); e = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        if let total = SystemInfo.storage()?.total {
            let gb = total / 1_000_000_000
            m.diskGB = [128, 256, 512, 1024, 2048, 4096, 8192].first { Double($0) >= gb * 0.95 } ?? Int(gb)
        }
        return m
    }

    static func loadModelName(_ done: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPHardwareDataType", "-json"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hw = (json["SPHardwareDataType"] as? [[String: Any]])?.first,
                  let name = hw["machine_name"] as? String else { return }
            DispatchQueue.main.async { done(name) }
        }
    }

    var diskText: String { diskGB >= 1024 ? "\(diskGB / 1024) TB" : "\(diskGB) GB" }
    var shortChip: String { chip.replacingOccurrences(of: "Apple ", with: "") }
    var summary: String { "\(shortChip) · \(memoryGB) GB · \(diskText)" }
    var detail: String {
        let cpu = eCores > 0 ? L("\(pCores + eCores) 核 CPU（\(pCores)P+\(eCores)E）", "\(pCores + eCores)-core CPU (\(pCores)P+\(eCores)E)")
                             : L("\(pCores) 核 CPU", "\(pCores)-core CPU")
        let gpu = gpuCores > 0 ? " · " + L("\(gpuCores) 核 GPU", "\(gpuCores)-core GPU") : ""
        return cpu + gpu + " · " + os
    }
}
