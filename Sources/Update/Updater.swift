import AppKit

final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var autoUpdate: Bool {
        didSet {
            UserDefaults.standard.set(autoUpdate, forKey: Self.autoUpdateKey)
            onChange()
            if autoUpdate { check(interactive: false) }
        }
    }
    var onChange: () -> Void = {}

    private static let autoUpdateKey = "autoUpdate"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let firstCheckDelay: TimeInterval = 15
    private static let checkInterval: TimeInterval = 6 * 3600
    private var timer: Timer?
    private var pending: Release?

    private init() {
        autoUpdate = UserDefaults.standard.object(forKey: Self.autoUpdateKey) as? Bool ?? true
    }

    var statusText: String {
        switch phase {
        case .idle:
            guard let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date else { return "" }
            return L("上次检查：", "Last checked: ") + last.formatted(date: .abbreviated, time: .shortened)
        case .checking: return L("正在检查…", "Checking…")
        case .upToDate: return L("已是最新版本", "Up to date")
        case .available(let v): return L("发现新版本 \(v)", "Version \(v) available")
        case .downloading(let v): return L("正在下载 \(v)…", "Downloading \(v)…")
        case .failed(let message): return message
        }
    }

    var busy: Bool {
        switch phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    func start() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckDelay) { [weak self] in self?.scheduledCheck() }
        let t = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.scheduledCheck()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func checkNow() { check(interactive: true) }

    private func scheduledCheck() {
        guard autoUpdate else { return }
        check(interactive: false)
    }

    private func check(interactive: Bool) {
        guard !busy else { return }
        set(.checking)
        Task {
            do {
                let release = try await ReleaseFeed.fetchLatest()
                await MainActor.run { self.handle(release, interactive: interactive) }
            } catch {
                let message = L("检查更新失败：", "Update check failed: ") + error.localizedDescription
                await MainActor.run {
                    self.set(.failed(message))
                    if interactive { self.alertFailure(L("无法检查更新", "Couldn't check for updates")) }
                }
            }
        }
    }

    @MainActor private func handle(_ release: Release, interactive: Bool) {
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        guard ReleaseFeed.isNewer(release.version, than: ReleaseFeed.currentVersion) else {
            set(.upToDate)
            if interactive { alertUpToDate() }
            return
        }
        pending = release
        set(.available(release.version))
        if interactive { offer(release) } else if autoUpdate { install(release, interactive: false) }
    }

    private func set(_ next: Phase) {
        phase = next
        onChange()
    }

    func installPending() {
        guard let release = pending, !busy else { return }
        install(release, interactive: true)
    }

    private func install(_ release: Release, interactive: Bool) {
        set(.downloading(release.version))
        Task.detached {
            do {
                let app = try await UpdateInstaller.prepare(release)
                await MainActor.run {
                    do { try UpdateInstaller.installAndRelaunch(app) } catch { self.installFailed(error, interactive: interactive) }
                }
            } catch {
                await MainActor.run { self.installFailed(error, interactive: interactive) }
            }
        }
    }

    @MainActor private func installFailed(_ error: Error, interactive: Bool) {
        set(.failed(L("更新失败：", "Update failed: ") + error.localizedDescription))
        if interactive { alertFailure(L("更新失败", "Update failed")) }
    }

    @MainActor private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = L("MenuRunner \(release.version) 可以更新了", "MenuRunner \(release.version) is available")
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = L("当前版本 \(ReleaseFeed.currentVersion)。", "You have \(ReleaseFeed.currentVersion).")
            + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(600)))
        alert.addButton(withTitle: L("立即更新", "Update Now"))
        alert.addButton(withTitle: L("稍后", "Later"))
        alert.addButton(withTitle: L("查看发布页", "View Release"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release, interactive: true)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    @MainActor private func alertUpToDate() {
        let alert = NSAlert()
        alert.messageText = L("已是最新版本", "You're up to date")
        alert.informativeText = L("MenuRunner \(ReleaseFeed.currentVersion) 是最新版本。", "MenuRunner \(ReleaseFeed.currentVersion) is the latest version.")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @MainActor private func alertFailure(_ title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = statusText
        alert.addButton(withTitle: L("好", "OK"))
        alert.addButton(withTitle: L("打开发布页", "Open Releases"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(ReleaseFeed.releasesPage) }
    }
}
