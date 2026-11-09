import Foundation
import Security

enum APIKeyStore {
    private static let service = "local.joey.menurunner.ai"

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MenuRunner/ai-keys.json")
    }()

    private static func readAll() -> [String: String]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func writeAll(_ keys: [String: String]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(keys) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func load(_ account: String) -> String {
        if let keys = readAll() { return keys[account] ?? "" }
        var migrated: [String: String] = [:]
        for a in AIProvider.allCases.map(\.rawValue) {
            let k = legacyLoad(a)
            if !k.isEmpty { migrated[a] = k }
        }
        writeAll(migrated)
        return migrated[account] ?? ""
    }

    static func save(_ key: String, for account: String) {
        var keys = readAll() ?? [:]
        guard keys[account, default: ""] != key else { return }
        keys[account] = key.isEmpty ? nil : key
        writeAll(keys)
    }

    private static func legacyLoad(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
