import AppKit

final class StatusVisibility {
    private var observer: NSObjectProtocol?
    private(set) var visible = true
    var onChange: ((Bool) -> Void)?

    func watch(_ window: NSWindow?) {
        guard let window else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                          object: window, queue: .main) { [weak self] n in
            guard let self, let w = n.object as? NSWindow else { return }
            let v = w.occlusionState.contains(.visible)
            guard v != self.visible else { return }
            self.visible = v
            self.onChange?(v)
        }
    }
}
