import AppKit
import SwiftUI

final class SidePanel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

final class AnalysisPanel: NSObject {
    static let shared = AnalysisPanel()
    static let width: CGFloat = 740
    private static let gap: CGFloat = 8
    private static let edge: CGFloat = 8
    private static let maxHeight: CGFloat = 920
    private static let slide: CGFloat = 28
    private static let cornerRadius: CGFloat = 24

    let model = AnalysisModel()
    private var panel: SidePanel?

    var isShown: Bool { panel?.isVisible == true }

    func show(spec: MachineSpec, beside anchor: NSRect, screen: NSScreen?) {
        model.spec = spec
        model.refresh()
        let p = panel ?? makePanel()
        panel = p
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = min(visible.height - Self.edge * 2, Self.maxHeight)
        let x = max(visible.minX + Self.edge, anchor.minX - Self.gap - Self.width)
        let y = max(visible.minY + Self.edge, min(anchor.maxY, visible.maxY - Self.edge) - height)
        let target = NSRect(x: x, y: y, width: Self.width, height: height)
        installEditMenu()
        NSApp.activate(ignoringOtherApps: true)
        guard !p.isVisible else {
            p.setFrame(target, display: true)
            p.makeKeyAndOrderFront(nil)
            return
        }
        p.setFrame(target.offsetBy(dx: Self.slide, dy: 0), display: false)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.24
            c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
            p.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        model.saveKey()
        let frame = p.frame
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.18
            c.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(frame.offsetBy(dx: Self.slide, dy: 0), display: true)
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            p.alphaValue = 1
            p.setFrame(frame, display: false)
        })
    }

    var onClose: () -> Void = {}

    private func makePanel() -> SidePanel {
        let p = SidePanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 800),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        p.onEscape = { [weak self] in self?.onClose() }
        let glass = NSGlassEffectView(frame: p.contentLayoutRect)
        glass.cornerRadius = Self.cornerRadius
        glass.style = .regular
        glass.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: AnalysisView(m: model, onClose: { [weak self] in self?.onClose() }))
        host.sizingOptions = []
        glass.contentView = host
        p.contentView = glass
        return p
    }

    private func installEditMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("编辑", "Edit"))
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
