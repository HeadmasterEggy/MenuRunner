import AppKit

enum UpdateInstaller {
    enum InstallError: LocalizedError {
        case tool(String, Int32)
        case noApp
        case wrongApp(String)
        case notWritable(String)
        var errorDescription: String? {
            switch self {
            case .tool(let name, let code): return L("\(name) 失败（\(code)）", "\(name) failed (\(code))")
            case .noApp: return L("下载的文件里没有 MenuRunner.app", "The download does not contain MenuRunner.app")
            case .wrongApp(let detail): return L("下载的 App 校验失败：\(detail)", "Downloaded app failed verification: \(detail)")
            case .notWritable(let path): return L("没有权限写入 \(path)", "No permission to write to \(path)")
            }
        }
    }

    static var installedApp: URL { Bundle.main.bundleURL }

    static func prepare(_ release: Release) async throws -> URL {
        let parent = installedApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw InstallError.notWritable(parent.path) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MenuRunnerUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            return try await stage(release, in: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    private static func stage(_ release: Release, in work: URL) async throws -> URL {
        let (downloaded, response) = try await URLSession.shared.download(from: release.assetURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ReleaseFeed.FeedError.badResponse(code) }
        let archive = work.appendingPathComponent(release.assetName)
        try FileManager.default.moveItem(at: downloaded, to: archive)
        let staged = work.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        if release.assetName.hasSuffix(".dmg") {
            try extractDiskImage(archive, into: staged, work: work)
        } else {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, staged.path])
        }
        let app = try findApp(in: staged)
        try verify(app, expected: release.version)
        return app
    }

    @MainActor static func installAndRelaunch(_ newApp: URL) throws {
        let target = installedApp
        let backup = target.deletingLastPathComponent().appendingPathComponent(".MenuRunner-old-\(UUID().uuidString).app")
        let script = """
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/mv \(quoted(target.path)) \(quoted(backup.path)) || exit 1
        if /usr/bin/ditto \(quoted(newApp.path)) \(quoted(target.path)); then
          /bin/rm -rf \(quoted(backup.path))
        else
          /bin/rm -rf \(quoted(target.path))
          /bin/mv \(quoted(backup.path)) \(quoted(target.path))
        fi
        /usr/bin/xattr -dr com.apple.quarantine \(quoted(target.path)) 2>/dev/null
        /usr/bin/open \(quoted(target.path))
        /bin/rm -rf \(quoted(newApp.deletingLastPathComponent().deletingLastPathComponent().path))
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        NSApp.terminate(nil)
    }

    private static func extractDiskImage(_ image: URL, into staged: URL, work: URL) throws {
        let mount = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let app = try findApp(in: mount)
        try run("/usr/bin/ditto", [app.path, staged.appendingPathComponent(app.lastPathComponent).path])
    }

    private static func findApp(in folder: URL) throws -> URL {
        let items = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.lastPathComponent == "MenuRunner.app" }) ?? items.first(where: { $0.pathExtension == "app" })
        else { throw InstallError.noApp }
        return app
    }

    private static func verify(_ app: URL, expected version: String) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
            throw InstallError.wrongApp("Info.plist")
        }
        let bundleID = info["CFBundleIdentifier"] as? String
        guard bundleID == Bundle.main.bundleIdentifier else { throw InstallError.wrongApp(bundleID ?? "bundle id") }
        let found = info["CFBundleShortVersionString"] as? String ?? ""
        guard ReleaseFeed.components(found) == ReleaseFeed.components(version) else {
            throw InstallError.wrongApp(L("版本是 \(found)", "version is \(found)"))
        }
        do { try run("/usr/bin/codesign", ["--verify", "--deep", app.path]) }
        catch { throw InstallError.wrongApp(L("签名无效", "invalid signature")) }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw InstallError.tool(URL(fileURLWithPath: tool).lastPathComponent, p.terminationStatus) }
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
