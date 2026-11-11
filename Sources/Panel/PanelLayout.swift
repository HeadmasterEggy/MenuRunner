import Foundation

final class PanelLayout: ObservableObject {
    static let shared = PanelLayout()
    private static let orderKey = "panelCardOrder"
    private static let hiddenKey = "panelCardHidden"

    @Published private(set) var order: [PanelCard]
    @Published private(set) var hidden: Set<PanelCard>
    var onChange: () -> Void = {}

    private init() {
        let d = UserDefaults.standard
        let saved = (d.stringArray(forKey: Self.orderKey) ?? []).compactMap(PanelCard.init(rawValue:))
        var seen = Set<PanelCard>()
        let unique = saved.filter { seen.insert($0).inserted }
        order = unique + PanelCard.allCases.filter { !seen.contains($0) }
        hidden = Set((d.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(PanelCard.init(rawValue:)))
    }

    var visible: [PanelCard] { order.filter { !hidden.contains($0) } }

    var isDefault: Bool { order == PanelCard.allCases && hidden.isEmpty }

    var rows: [[PanelCard]] {
        var rows: [[PanelCard]] = []
        var waiting: PanelCard?
        for card in visible {
            if card.isHalfWidth {
                if let left = waiting { rows.append([left, card]); waiting = nil } else { waiting = card }
                continue
            }
            if let left = waiting { rows.append([left]); waiting = nil }
            rows.append([card])
        }
        if let left = waiting { rows.append([left]) }
        return rows
    }

    func isShown(_ card: PanelCard) -> Bool { !hidden.contains(card) }

    func setShown(_ card: PanelCard, _ shown: Bool) {
        guard shown == hidden.contains(card) else { return }
        if shown { hidden.remove(card) } else { hidden.insert(card) }
        save()
    }

    func move(_ card: PanelCard, onto target: PanelCard) {
        guard card != target, let from = order.firstIndex(of: card), let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    func reset() {
        order = PanelCard.allCases
        hidden = []
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(order.map(\.rawValue), forKey: Self.orderKey)
        d.set(PanelCard.allCases.filter(hidden.contains).map(\.rawValue), forKey: Self.hiddenKey)
        onChange()
    }
}
