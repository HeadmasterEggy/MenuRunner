import AppKit
import QuartzCore
import IOKit

@_silgen_name("IOHIDEventSystemClientCreate") private func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func IOHIDEventSystemClientSetMatching(_ c: AnyObject, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func IOHIDEventSystemClientCopyServices(_ c: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func IOHIDServiceClientCopyProperty(_ s: AnyObject, _ k: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func IOHIDServiceClientCopyEvent(_ s: AnyObject, _ t: Int64, _ o: Int32, _ x: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ e: AnyObject, _ f: Int32) -> Double

struct Temps { var soc: Double?, battery: Double?, ssd: Double? }

final class TempMonitor {
    static let shared = TempMonitor()
    private let client: AnyObject? = {
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        _ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        return c
    }()

    private let lock = NSLock()
    private var cached: [(AnyObject, String)] = []
    private var cachedAt: CFTimeInterval = -1000
    private func sensorList() -> [(AnyObject, String)] {
        lock.lock(); defer { lock.unlock() }
        let now = CACurrentMediaTime()
        if now - cachedAt < 30, !cached.isEmpty { return cached }
        guard let client, let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        cached = services.compactMap { s in
            (IOHIDServiceClientCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String).map { (s, $0) }
        }
        cachedAt = now
        return cached
    }

    func readAll() -> [(String, Double)] {
        var g: [String: [Double]] = [:]
        for (s, name) in sensorList() {
            guard let e = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            let v = IOHIDEventGetFloatValue(e, 15 << 16)
            if v > 0 && v < 150 { g[name, default: []].append(v) }
        }
        return g.map { ($0.key, $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    func read() -> Temps {
        var soc: [Double] = [], bat: [Double] = [], ssd: [Double] = []
        for (s, name) in sensorList() where name.hasPrefix("PMU tdie") || name.hasPrefix("gas gauge battery") || name.hasPrefix("NAND") {
            guard let e = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
            let v = IOHIDEventGetFloatValue(e, 15 << 16)
            guard v > 0 && v < 150 else { continue }
            if name.hasPrefix("PMU tdie") { soc.append(v) }
            else if name.hasPrefix("gas gauge battery") { bat.append(v) }
            else if name.hasPrefix("NAND") { ssd.append(v) }
        }
        func avg(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        return Temps(soc: soc.max(), battery: avg(bat), ssd: avg(ssd))
    }
}
