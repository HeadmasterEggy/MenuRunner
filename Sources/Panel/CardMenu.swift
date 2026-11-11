import AppKit

final class CardMenu: NSObject {
    private let card: PanelCard

    private init(card: PanelCard) { self.card = card }

    static func make(for card: PanelCard) -> NSMenu {
        let handler = CardMenu(card: card)
        let layout = PanelLayout.shared
        let narrow = layout.isNarrow(card)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(handler.item(narrow ? L("放大为宽卡片", "Make Wide") : L("缩小为小卡片", "Make Small"),
                                  symbol: narrow ? "rectangle" : "square", action: #selector(toggleSize)))
        menu.addItem(handler.item(L("隐藏此卡片", "Hide Card"), symbol: "eye.slash", action: #selector(hide)))
        return menu
    }

    private func item(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.target = self
        item.representedObject = self
        return item
    }

    @objc private func toggleSize() {
        let layout = PanelLayout.shared
        layout.setNarrow(card, !layout.isNarrow(card))
    }

    @objc private func hide() { PanelLayout.shared.setShown(card, false) }
}
