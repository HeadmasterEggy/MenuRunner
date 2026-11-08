import AppKit
import SystemConfiguration

enum SystemDetail {
    static func rows(_ spec: MachineSpec) -> [(String, String)] {
        let up = Int(ProcessInfo.processInfo.systemUptime)
        let uptime = up >= 86400 ? L("\(up / 86400) 天 \(up % 86400 / 3600) 小时", "\(up / 86400)d \(up % 86400 / 3600)h")
                                 : L("\(up / 3600) 小时 \(up % 3600 / 60) 分", "\(up / 3600)h \(up % 3600 / 60)m")
        let screens = NSScreen.screens.map { s -> String in
            let px = s.frame.size.applying(.init(scaleX: s.backingScaleFactor, y: s.backingScaleFactor))
            return "\(s.localizedName) \(Int(px.width))×\(Int(px.height))"
        }
        var r: [(String, String)] = [
            (L("机型", "Model"), spec.model),
            (L("型号标识", "Model Identifier"), MachineSpec.sysctlString("hw.model")),
            (L("芯片", "Chip"), spec.chip),
            ("CPU", spec.eCores > 0 ? L("\(spec.pCores + spec.eCores) 核（\(spec.pCores) 性能 + \(spec.eCores) 能效）", "\(spec.pCores + spec.eCores) cores (\(spec.pCores)P + \(spec.eCores)E)") : "\(spec.pCores)"),
            ("GPU", spec.gpuCores > 0 ? L("\(spec.gpuCores) 核", "\(spec.gpuCores) cores") : "--"),
            (L("内存", "Memory"), "\(spec.memoryGB) GB"),
            (L("硬盘", "Disk"), spec.diskText),
            (L("系统", "macOS"), "\(spec.os) (\(MachineSpec.sysctlString("kern.osversion")))"),
            (L("已运行", "Uptime"), uptime),
            (L("主机名", "Computer Name"), computerName),
        ]
        for (i, s) in screens.prefix(2).enumerated() { r.append((i == 0 ? L("显示器", "Displays") : "", s)) }
        return r
    }

    private static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "--"
    }
}
