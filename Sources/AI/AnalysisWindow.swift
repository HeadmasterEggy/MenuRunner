import AppKit
import SwiftUI

final class AnalysisWindow: NSObject, NSWindowDelegate {
    static let shared = AnalysisWindow()
    let model = AnalysisModel()
    private var window: NSWindow?

    func show(spec: MachineSpec) {
        model.spec = spec
        model.refresh()
        let w = window ?? makeWindow()
        window = w
        installEditMenu()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 860),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = L("AI 系统分析", "AI System Analysis")
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: AnalysisView(m: model))
        w.center()
        return w
    }

    func windowWillClose(_ notification: Notification) { model.saveKey() }

    private func installEditMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        edit.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
