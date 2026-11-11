import Foundation

final class PanelLayout: ObservableObject {
    static let shared = PanelLayout()
    private static let orderKey = "panelCardOrder"
    private static let hiddenKey = "panelCardHidden"
    private static let narrowKey = "panelCardNarrow"
    private static let defaultNarrow = Set(PanelCard.allCases.filter(\.isNarrowByDefault))

    @Published private(set) var order: [PanelCard]
    @Published private(set) var hidden: Set<PanelCard>
    @Published private(set) var narrow: Set<PanelCard>
    var onChange: () -> Void = {}

    private init() {
        let d = UserDefaults.standard
        let saved = (d.stringArray(forKey: Self.orderKey) ?? []).compactMap(PanelCard.init(rawValue:))
        var seen = Set<PanelCard>()
        let unique = saved.filter { seen.insert($0).inserted }
        order = unique + PanelCard.allCases.filter { !seen.contains($0) }
        hidden = Set((d.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(PanelCard.init(rawValue:)))
        narrow = d.stringArray(forKey: Self.narrowKey).map { Set($0.compactMap(PanelCard.init(rawValue:))) } ?? Self.defaultNarrow
    }

    var visible: [PanelCard] { order.filter { !hidden.contains($0) } }

    var isDefault: Bool { order == PanelCard.allCases && hidden.isEmpty && narrow == Self.defaultNarrow }

    var rows: [[PanelCard]] { rows(for: visible) }

    func isNarrow(_ card: PanelCard) -> Bool { narrow.contains(card) }

    func setNarrow(_ card: PanelCard, _ isNarrow: Bool) {
        guard isNarrow != narrow.contains(card) else { return }
        if isNarrow { narrow.insert(card) } else { narrow.remove(card) }
        save()
    }

    func rows(for visible: [PanelCard]) -> [[PanelCard]] {
        var rows: [[PanelCard]] = []
        var waiting: PanelCard?
        for card in visible {
            if narrow.contains(card) {
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

    func reorderVisible(_ cards: [PanelCard]) {
        var next = cards.makeIterator()
        let reordered = order.map { hidden.contains($0) ? $0 : (next.next() ?? $0) }
        guard reordered != order, Set(reordered).count == order.count else { return }
        order = reordered
        save()
    }

    func reset() {
        order = PanelCard.allCases
        hidden = []
        narrow = Self.defaultNarrow
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(order.map(\.rawValue), forKey: Self.orderKey)
        d.set(PanelCard.allCases.filter(hidden.contains).map(\.rawValue), forKey: Self.hiddenKey)
        d.set(PanelCard.allCases.filter(narrow.contains).map(\.rawValue), forKey: Self.narrowKey)
        onChange()
    }
}
