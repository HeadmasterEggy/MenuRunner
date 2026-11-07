import Foundation

struct Release {
    let version: String
    let notes: String
    let pageURL: URL
    let assetURL: URL
    let assetName: String
}

enum ReleaseFeed {
    static let owner = "HeadmasterEggy"
    static let repo = "MenuRunner"
    static var latestURL: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")! }
    static var releasesPage: URL { URL(string: "https://github.com/\(owner)/\(repo)/releases")! }

    static var currentVersion: String {
        if let i = CommandLine.arguments.firstIndex(of: "--pretend-version"), i + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[i + 1]
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    enum FeedError: LocalizedError {
        case badResponse(Int)
        case noAsset
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return L("GitHub 返回 \(code)", "GitHub returned \(code)")
            case .noAsset: return L("这个版本没有可安装的文件", "This release has no installable file")
            }
        }
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MenuRunner/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw FeedError.badResponse(code) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let installable = payload.assets.first { $0.name.hasSuffix(".zip") && $0.name.hasPrefix(repo) }
            ?? payload.assets.first { $0.name.hasSuffix(".dmg") }
        guard let asset = installable else { throw FeedError.noAsset }
        return Release(version: normalized(payload.tag_name), notes: payload.body ?? "", pageURL: payload.html_url,
                       assetURL: asset.browser_download_url, assetName: asset.name)
    }

    static func normalized(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    static func components(_ version: String) -> [Int] {
        normalized(version).split(separator: ".").map { part in Int(part.prefix { $0.isNumber }) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
