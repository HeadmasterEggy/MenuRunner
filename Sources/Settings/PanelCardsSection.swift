import SwiftUI
import UniformTypeIdentifiers

struct PanelCardsSection: View {
    var langTick = 0
    @ObservedObject var layout = PanelLayout.shared
    @State private var dragging: PanelCard?

    var body: some View {
        Section {
            ForEach(layout.order) { card in
                row(card)
                    .onDrag {
                        dragging = card
                        return NSItemProvider(object: card.rawValue as NSString)
                    }
                    .onDrop(of: [.text], delegate: PanelCardDropDelegate(target: card, layout: layout, dragging: $dragging))
            }
            Button {
                withAnimation(.snappy) { layout.reset() }
            } label: {
                Label(L("恢复默认", "Restore Default"), systemImage: "arrow.counterclockwise")
            }
            .disabled(layout.isDefault)
        } header: {
            Text(L("面板卡片", "Panel Cards"))
        } footer: {
            Text(L("在面板上直接拖动卡片，或在这里拖动调整顺序；关闭开关可隐藏卡片", "Drag cards right in the panel, or drag rows here, to reorder. Turn a card off to hide it."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ card: PanelCard) -> some View {
        let shown = layout.isShown(card)
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Image(systemName: card.symbol)
                .foregroundStyle(Color(nsColor: card.tint))
                .frame(width: 20)
            Text(card.title)
                .foregroundStyle(shown ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(get: { layout.isShown(card) },
                                     set: { on in withAnimation(.snappy) { layout.setShown(card, on) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .contentShape(Rectangle())
    }
}

private struct PanelCardDropDelegate: DropDelegate {
    let target: PanelCard
    let layout: PanelLayout
    @Binding var dragging: PanelCard?

    func dropEntered(info: DropInfo) {
        guard let card = dragging, card != target else { return }
        withAnimation(.snappy) { layout.move(card, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
