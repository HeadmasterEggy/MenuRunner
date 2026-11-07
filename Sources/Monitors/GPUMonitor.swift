import AppKit
import IOKit

enum GPUMonitor {
    static func usage() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let v = stats["Device Utilization %"] as? Int else { continue }
            best = max(best ?? 0, Double(v) / 100)
        }
        return best
    }

    static func memoryInUse() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var total: Double?
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any], let v = (stats["In use system memory"] as? NSNumber)?.doubleValue {
                total = (total ?? 0) + v
            }
        }
        return total
    }
}
