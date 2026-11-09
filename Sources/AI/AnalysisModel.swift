import AppKit

final class AnalysisModel: ObservableObject {
    static let ranges = [24, 72, 168, 336]
    static let shareLimit = 7

    @Published var provider: AIProvider { didSet { defaults.set(provider.rawValue, forKey: "aiProvider"); loadKey() } }
    @Published var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "aiClaudeModel") } }
    @Published var openAIModel: String { didSet { defaults.set(openAIModel, forKey: "aiOpenAIModel") } }
    @Published var openAIBase: String { didSet { defaults.set(openAIBase, forKey: "aiOpenAIBase") } }
    @Published var rangeHours: Int { didSet { defaults.set(rangeHours, forKey: "aiRangeHours"); refresh() } }
    @Published var apiKey = ""
    @Published var running = false
    @Published var result: String { didSet { parsed = AnalysisResult.parse(result) } }
    @Published var parsed: AnalysisResult?
    @Published var buckets: [PowerBucket] = []
    @Published var metric: Metric = .power
    @Published var rankKind: RankKind = .energy
    @Published var selectedApp: String?
    @Published var category: String?
    @Published var focusFinding: String?
    @Published var resultDate: Date?
    @Published var error: String?
    @Published var recordedHours = 0.0
    var spec = MachineSpec.basic()

    private let defaults = UserDefaults.standard
    private var task: URLSessionDataTask?

    init() {
        let d = UserDefaults.standard
        provider = AIProvider(rawValue: d.string(forKey: "aiProvider") ?? "") ?? .anthropic
        claudeModel = d.string(forKey: "aiClaudeModel") ?? AIClient.defaultClaudeModel
        openAIModel = d.string(forKey: "aiOpenAIModel") ?? ""
        openAIBase = d.string(forKey: "aiOpenAIBase") ?? AIClient.defaultOpenAIBase
        let r = d.integer(forKey: "aiRangeHours")
        rangeHours = Self.ranges.contains(r) ? r : 168
        result = d.string(forKey: "aiLastResult") ?? ""
        resultDate = d.object(forKey: "aiLastResultDate") as? Date
        parsed = AnalysisResult.parse(result)
        loadKey()
    }

    func refresh() {
        recordedHours = PowerRecorder.shared.recordedSeconds(hours: Double(PowerRecorder.retention / 3600)) / 3600
        buckets = PowerRecorder.shared.recent(hours: Double(rangeHours))
    }

    var cores: Int { max(spec.pCores + spec.eCores, 1) }
    var recordedSeconds: Double { buckets.reduce(0) { $0 + $1.seconds } }
    var ranking: [EnergyShare] { PowerStats.ranking(buckets, kind: rankKind, limit: Self.shareLimit) }
    var energyRanking: [EnergyShare] { PowerStats.ranking(buckets, kind: .energy, limit: Self.shareLimit) }
    var step: TimeInterval {
        guard let first = buckets.map(\.start).min(), let last = buckets.map(\.end).max() else { return PowerStats.step(hours: rangeHours) }
        return PowerStats.step(hours: min(rangeHours, Int(ceil(last.timeIntervalSince(first) / 3600))))
    }
    var trend: [TrendPoint] { PowerStats.trend(buckets, metric: metric, step: step, app: selectedApp, cores: cores) }
    var daily: [DailyEnergy] { PowerStats.daily(buckets) }
    var availableMetrics: [Metric] { Metric.allCases.filter { PowerStats.average(buckets, metric: $0) != nil } }

    func toggle(app: String) {
        guard app != PowerStats.otherName else { return }
        selectedApp = selectedApp == app ? nil : app
    }

    static func metrics(for category: String) -> [Metric] {
        switch category {
        case "power": return [.power]
        case "cpu": return [.cpu]
        case "gpu": return [.gpu]
        case "memory": return [.memory, .pressure]
        case "thermal": return [.socTemp, .batteryTemp, .fan]
        case "battery": return [.battery]
        case "network": return [.netDown, .netUp]
        default: return []
        }
    }

    static func category(for metric: Metric) -> String? {
        AnalysisResult.categories.first { metrics(for: $0).contains(metric) }
    }

    func show(category c: String) {
        let options = Self.metrics(for: c)
        guard !options.contains(metric), let first = options.first(where: availableMetrics.contains) else { return }
        metric = first
    }

    func toggle(category c: String) {
        category = category == c ? nil : c
        focusFinding = nil
        show(category: c)
    }

    func toggle(finding f: Finding) {
        focusFinding = focusFinding == f.id ? nil : f.id
        if focusFinding != nil, let c = f.category { show(category: c) }
    }

    var chartFindings: [(Int, Finding, ClosedRange<Date>)] {
        guard let r = parsed, let c = Self.category(for: metric) else { return [] }
        return r.findings.enumerated().compactMap { i, f in
            guard f.category == c, let range = f.range else { return nil }
            return (i + 1, f, range)
        }
    }

    private func loadKey() { apiKey = APIKeyStore.load(provider.rawValue) }

    func saveKey() { APIKeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.rawValue) }

    var model: String { provider == .anthropic ? claudeModel : openAIModel.trimmingCharacters(in: .whitespaces) }

    func analyze() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .anthropic && key.isEmpty { error = L("请先填写 API Key", "Enter an API key first"); return }
        if model.isEmpty { error = L("请先填写模型名称", "Enter a model name first"); return }
        saveKey()
        let buckets = PowerRecorder.shared.recent(hours: Double(rangeHours))
        guard !buckets.isEmpty else { error = L("还没有记录到数据，让 MenuRunner 多运行一会儿再试", "No data recorded yet; let MenuRunner run for a while"); return }
        let request = AIRequest(provider: provider, model: model, key: key, baseURL: openAIBase,
                                system: PowerReport.systemPrompt, prompt: PowerReport.build(buckets, spec: spec))
        error = nil
        running = true
        task = AIClient.send(request) { [weak self] r in
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                self.running = false
                switch r {
                case .success(let text):
                    self.category = nil
                    self.focusFinding = nil
                    self.result = text
                    self.refresh()
                    self.resultDate = Date()
                    self.defaults.set(text, forKey: "aiLastResult")
                    self.defaults.set(self.resultDate, forKey: "aiLastResultDate")
                case .failure(let e):
                    self.error = e.localizedDescription
                }
            }
        }
    }

    func cancel() {
        running = false
        task?.cancel()
        task = nil
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    static func rangeTitle(_ h: Int) -> String {
        h < 48 ? L("\(h) 小时", "\(h) h") : L("\(h / 24) 天", "\(h / 24) days")
    }

    static func spanText(_ hours: Double) -> String {
        let total = Int(hours * 60)
        let d = total / 1440, h = total % 1440 / 60, m = total % 60
        if d > 0 { return L("\(d) 天 \(h) 小时", "\(d)d \(h)h") }
        if h > 0 { return L("\(h) 小时 \(m) 分", "\(h)h \(m)m") }
        return L("\(m) 分钟", "\(m) min")
    }
}
