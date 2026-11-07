import Foundation
import IOKit

private struct SMCVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
private struct SMCLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpuLimit: UInt32 = 0, gpuLimit: UInt32 = 0, memLimit: UInt32 = 0 }
private struct SMCKeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }

private struct SMCParam {
    var key: UInt32 = 0
    var version = SMCVersion()
    var limitData = SMCLimitData()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMC {
    static let shared = SMC()

    private static let callSelector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var infoCache: [UInt32: SMCKeyInfo] = [:]

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != kIOReturnSuccess { connection = 0 }
    }

    var available: Bool { connection != 0 }

    private static func code(_ s: String) -> UInt32 { s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) } }

    private static func typeName(_ t: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((t >> $0) & 0xff) }, encoding: .ascii) ?? ""
    }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        var output = SMCParam()
        var size = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(connection, Self.callSelector, &input, MemoryLayout<SMCParam>.stride, &output, &size)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private func keyInfo(_ key: UInt32) -> SMCKeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = SMCParam()
        input.key = key
        input.command = Self.readKeyInfoCommand
        guard let out = call(&input) else { return nil }
        infoCache[key] = out.keyInfo
        return out.keyInfo
    }

    func read(_ name: String) -> (type: String, bytes: [UInt8])? {
        guard available else { return nil }
        lock.lock(); defer { lock.unlock() }
        let key = Self.code(name)
        guard let info = keyInfo(key), info.dataSize > 0 else { return nil }
        var input = SMCParam()
        input.key = key
        input.keyInfo.dataSize = info.dataSize
        input.command = Self.readBytesCommand
        guard var out = call(&input) else { return nil }
        let count = min(Int(info.dataSize), 32)
        let bytes = withUnsafeBytes(of: &out.bytes) { Array($0.prefix(count)) }
        return (Self.typeName(info.dataType), bytes)
    }

    func number(_ name: String) -> Double? {
        guard let (type, b) = read(name) else { return nil }
        switch type {
        case "flt " where b.count >= 4:
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "fpe2" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "ui8 " where b.count >= 1:
            return Double(b[0])
        case "ui16" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }
}
