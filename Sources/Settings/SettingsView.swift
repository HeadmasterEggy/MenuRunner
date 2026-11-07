import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var values: [String: String]
    @Published var login: Bool
    @Published var langTick = 0
    var apply: (String, String) -> Void = { _, _ in }
    var setLogin: (Bool) -> Bool = { $0 }
    var options: (String) -> [(id: String, name: String)] = { _ in [] }
    var openActivityMonitor: () -> Void = {}
    let runnerFrames: [String: [NSImage]] = Dictionary(uniqueKeysWithValues: Runner.all.map { ($0.id, $0.frames()) })

    init(values: [String: String], login: Bool) { self.values = values; self.login = login }

    func binding(_ key: String) -> Binding<String> {
        Binding(get: { self.values[key] ?? "" }, set: { v in self.values[key] = v; self.apply(key, v) })
    }
}

struct RunnerCard: View {
    let runner: Runner
    let frames: [NSImage]
    let selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let i = Int(ctx.date.timeIntervalSinceReferenceDate * 10) % max(frames.count, 1)
                Image(nsImage: frames[i])
                    .renderingMode(runner.template ? .template : .original)
                    .interpolation(.none)
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
                    .frame(height: 30)
            }
            .frame(width: 70, height: 38)
            Text(runner.displayName).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8).frame(width: 84)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    var width: CGFloat = 540
    var height: CGFloat = 770

    private func menuPicker(_ key: String, _ title: String, _ icon: String) -> some View {
        Picker(selection: m.binding(key)) {
            ForEach(m.options(key), id: \.id) { o in Text(o.name).tag(o.id) }
        } label: { Label(title, systemImage: icon) }
        .pickerStyle(.menu)
    }

    private func segmented(_ key: String, _ title: String, _ icon: String) -> some View {
        Picker(selection: m.binding(key)) {
            ForEach(m.options(key), id: \.id) { o in Text(o.name).tag(o.id) }
        } label: { Label(title, systemImage: icon) }
        .pickerStyle(.segmented)
    }

    var body: some View {
        let _ = m.langTick
        Form {
            Section(L("外观", "Appearance")) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Runner", systemImage: "figure.run")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: 8)], spacing: 8) {
                        ForEach(Runner.all, id: \.id) { r in
                            RunnerCard(runner: r, frames: m.runnerFrames[r.id] ?? [], selected: m.values["runner"] == r.id)
                                .onTapGesture { withAnimation(.snappy) { m.binding("runner").wrappedValue = r.id } }
                        }
                    }
                    .padding(.vertical, 2)
                }
                menuPicker("barMetric", L("菜单栏显示", "Menu Bar Shows"), "menubar.rectangle")
                menuPicker("barStyle", L("菜单栏样式", "Menu Bar Style"), "chart.xyaxis.line")
                menuPicker("speedSource", L("Runner 速度跟随", "Runner Speed Follows"), "speedometer")
            }
            Section(L("数据", "Data")) {
                segmented("refreshInterval", L("刷新频率", "Refresh Rate"), "arrow.clockwise")
                segmented("tempUnit", L("温度单位", "Temperature Unit"), "thermometer.medium")
                menuPicker("lang", "语言 / Language", "globe")
            }
            Section(L("系统", "System")) {
                Toggle(isOn: Binding(get: { m.login }, set: { m.login = m.setLogin($0) })) {
                    Label(L("开机自动启动", "Launch at Login"), systemImage: "power")
                }
                Button { m.openActivityMonitor() } label: {
                    Label(L("打开活动监视器", "Open Activity Monitor"), systemImage: "waveform.path.ecg")
                }
                LabeledContent {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--").foregroundStyle(.secondary)
                } label: { Label(L("版本", "Version"), systemImage: "info.circle") }
                LabeledContent {
                    Link("HeadmasterEggy/MenuRunner", destination: URL(string: "https://github.com/HeadmasterEggy/MenuRunner")!)
                } label: { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label(L("退出 MenuRunner", "Quit MenuRunner"), systemImage: "xmark.circle")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: width, height: height)
    }
}
