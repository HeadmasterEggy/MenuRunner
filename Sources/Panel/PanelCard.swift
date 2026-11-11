import AppKit

enum PanelCard: String, CaseIterable, Identifiable {
    case cpu, gpu, temps, memory, storage, battery, network, power

    var id: String { rawValue }

    var isHalfWidth: Bool {
        switch self {
        case .gpu, .temps, .storage, .battery: return true
        case .cpu, .memory, .network, .power: return false
        }
    }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .temps: return L("温度", "Temperature")
        case .memory: return L("内存", "Memory")
        case .storage: return L("存储", "Storage")
        case .battery: return L("电池", "Battery")
        case .network: return L("网络", "Network")
        case .power: return L("功耗", "Power")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .temps: return "thermometer.medium"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .network: return "network"
        case .power: return "bolt.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .cpu: return .systemBlue
        case .gpu: return .systemGreen
        case .temps: return .systemOrange
        case .memory: return .systemPurple
        case .storage: return .systemIndigo
        case .battery: return .systemGreen
        case .network: return .systemTeal
        case .power: return .systemYellow
        }
    }

    var detailKind: DetailKind {
        switch self {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .temps: return .temps
        case .memory: return .memory
        case .storage: return .storage
        case .battery: return .battery
        case .network: return .network
        case .power: return .power
        }
    }

    var animatesContinuously: Bool { self == .cpu || self == .gpu || self == .network }
}
