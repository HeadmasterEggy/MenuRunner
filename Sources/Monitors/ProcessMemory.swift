import AppKit

struct AppMemory { var name: String, path: String?, bytes: UInt64, processes: Int }

enum ProcessMemory {
    static func top(_ limit: Int) -> [AppMemory] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let got = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        var groups: [String: AppMemory] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(max(got, 0))) where pid > 0 {
            var usage = rusage_info_current()
            let r = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard r == 0, usage.ri_phys_footprint > 0 else { continue }
            let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = len > 0 ? String(cString: pathBuf) : ""
            var key: String, name: String, appPath: String?
            if let range = path.range(of: ".app/") {
                appPath = String(path[..<range.lowerBound]) + ".app"
                key = appPath!
                name = (appPath! as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            } else {
                name = (path as NSString).lastPathComponent
                if name.isEmpty {
                    var nameBuf = [CChar](repeating: 0, count: 256)
                    proc_name(pid, &nameBuf, UInt32(nameBuf.count))
                    name = String(cString: nameBuf)
                }
                key = path.isEmpty ? name : path
            }
            var g = groups[key] ?? AppMemory(name: name, path: appPath, bytes: 0, processes: 0)
            g.bytes += usage.ri_phys_footprint
            g.processes += 1
            groups[key] = g
        }
        return Array(groups.values.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    static func format(_ b: UInt64) -> String {
        let d = Double(b)
        return d >= 1_073_741_824 ? String(format: "%.2f GB", d / 1_073_741_824) : String(format: "%.0f MB", d / 1_048_576)
    }

    private static let iconSide: CGFloat = 32
    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 96
        return c
    }()
    private static let placeholder = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: nil)!

    static func icon(_ path: String?) -> NSImage {
        guard let path else { return placeholder }
        if let i = iconCache.object(forKey: path as NSString) { return i }
        let img = rasterize(NSWorkspace.shared.icon(forFile: path))
        iconCache.setObject(img, forKey: path as NSString)
        return img
    }

    private static func rasterize(_ source: NSImage) -> NSImage {
        let size = NSSize(width: iconSide, height: iconSide)
        let pixels = Int(iconSide * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }
}
