import AppKit

final class AnalysisModel: ObservableObject {
    static let ranges = [24, 72, 168, 336]
    static let shareLimit = 6

    @Published var provider: AIProvider { didSet { defaults.set(provider.rawValue, forKey: "aiProvider"); loadKey() } }
    @Published var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "aiClaudeModel") } }
    @Published var openAIModel: String { didSet { defaults.set(openAIModel, forKey: "aiOpenAIModel") } }
    @Published var openAIBase: String { didSet { defaults.set(openAIBase, forKey: "aiOpenAIBase") } }
    @Published var rangeHours: Int { didSet { defaults.set(rangeHours, forKey: "aiRangeHours"); refresh() } }
    @Published var apiKey = ""
    @Published var running = false
    @Published var result: String { didSet { parsed = AnalysisResult.parse(result) } }
    @Published var parsed: AnalysisResult?
    @Published var shares: [EnergyShare] = []
    @Published var trend: [TrendPoint] = []
    @Published var daily: [DailyEnergy] = []
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
        let buckets = PowerRecorder.shared.recent(hours: Double(rangeHours))
        shares = PowerStats.shares(buckets, limit: Self.shareLimit)
        trend = PowerStats.hourlyTrend(buckets)
        daily = PowerStats.daily(buckets)
    }

    var totalShareJoules: Double { shares.reduce(0) { $0 + $1.joules } }

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
