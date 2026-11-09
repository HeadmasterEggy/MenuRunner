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

    private static let releaseDelay: TimeInterval = 60
    private static let showDuration = 0.22
    private static let hideDuration = 0.16

    let model = AnalysisModel()
    private var panel: SidePanel?
    private var hiding = false
    private var generation = 0
    private var releaseWork: DispatchWorkItem?

    var isShown: Bool { panel?.isVisible == true && !hiding }

    func show(spec: MachineSpec, beside anchor: NSRect, screen: NSScreen?) {
        releaseWork?.cancel()
        releaseWork = nil
        generation += 1
        let g = generation
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
        if p.isVisible && !hiding {
            p.setFrame(target, display: true)
            p.makeKeyAndOrderFront(nil)
            return
        }
        hiding = false
        if !p.isVisible {
            p.alphaValue = 0
            p.setFrame(target.offsetBy(dx: Self.slide, dy: 0), display: false)
            p.contentView?.layoutSubtreeIfNeeded()
        } else {
            p.setFrame(NSRect(origin: p.frame.origin, size: target.size), display: false)
        }
        p.makeKeyAndOrderFront(nil)
        p.displayIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == g else { return }
            NSAnimationContext.runAnimationGroup { c in
                c.duration = Self.showDuration
                c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                p.animator().setFrame(target, display: false)
                p.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let p = panel, p.isVisible, !hiding else { return }
        hiding = true
        generation += 1
        let g = generation
        model.saveKey()
        let frame = p.frame
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = Self.hideDuration
            c.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(frame.offsetBy(dx: Self.slide, dy: 0), display: false)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == g else { return }
            self.hiding = false
            p.orderOut(nil)
            self.scheduleRelease()
        })
    }

    private func scheduleRelease() {
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.release() }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay, execute: work)
    }

    private func release() {
        releaseWork = nil
        guard let p = panel, !p.isVisible else { return }
        p.contentView = nil
        p.close()
        panel = nil
        model.release()
        DispatchQueue.main.async { _ = malloc_zone_pressure_relief(nil, 0) }
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
        let host = NSHostingView(rootView: AnalysisView(m: model, onClose: { [weak self] in self?.onClose() }))
        host.sizingOptions = []
        p.contentView = GlassBackground.window(frame: p.contentLayoutRect, cornerRadius: Self.cornerRadius, content: host)
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
