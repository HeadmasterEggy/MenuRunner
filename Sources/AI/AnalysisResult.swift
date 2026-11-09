import Foundation

enum Level: String, Codable, Comparable {
    case high, medium, low

    private var rank: Int { self == .high ? 0 : (self == .medium ? 1 : 2) }
    static func < (a: Level, b: Level) -> Bool { a.rank < b.rank }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self))?.lowercased() ?? ""
        self = Level(rawValue: raw) ?? .medium
    }
}

enum Verdict: String, Codable {
    case expected, watch, abnormal

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self))?.lowercased() ?? ""
        self = Verdict(rawValue: raw) ?? .watch
    }
}

struct Finding: Codable, Identifiable {
    var title: String
    var detail: String
    var severity: Level
    var category: String?
    var from: String?
    var to: String?
    var id: String { title + detail }

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let clean = s.filter { !$0.isLetter }.split(separator: " ").joined(separator: " ")
        return stampFormat.date(from: clean)
    }

    var range: ClosedRange<Date>? {
        guard let a = Self.date(from) else { return nil }
        let b = Self.date(to) ?? a
        return min(a, b)...max(a, b)
    }
}

struct Suggestion: Codable, Identifiable {
    var title: String
    var detail: String
    var impact: Level
    var id: String { title + detail }
}

struct AppVerdict: Codable, Identifiable {
    var name: String
    var verdict: Verdict
    var note: String
    var id: String { name }
}

struct AnalysisResult: Codable {
    var score: Int
    var headline: String
    var findings: [Finding]
    var suggestions: [Suggestion]
    var apps: [AppVerdict]
    var scores: [String: Int]

    static let categories = ["power", "cpu", "gpu", "memory", "thermal", "battery", "network"]

    enum CodingKeys: String, CodingKey { case score, headline, findings, suggestions, apps, scores }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = min(max((try? c.decode(Int.self, forKey: .score)) ?? Int((try? c.decode(Double.self, forKey: .score)) ?? 50), 0), 100)
        headline = (try? c.decode(String.self, forKey: .headline)) ?? ""
        findings = ((try? c.decode([Finding].self, forKey: .findings)) ?? []).sorted { $0.severity < $1.severity }
        suggestions = ((try? c.decode([Suggestion].self, forKey: .suggestions)) ?? []).sorted { $0.impact < $1.impact }
        apps = (try? c.decode([AppVerdict].self, forKey: .apps)) ?? []
        let raw = (try? c.decode([String: Double].self, forKey: .scores)) ?? [:]
        scores = raw.reduce(into: [:]) { $0[$1.key.lowercased()] = min(max(Int($1.value.rounded()), 0), 100) }
    }

    var orderedScores: [(String, Int)] {
        Self.categories.compactMap { c in scores[c].map { (c, $0) } }
    }

    func verdict(for app: String) -> AppVerdict? { apps.first { $0.name == app } }

    static func parse(_ text: String) -> AnalysisResult? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        let json = Data(text[open...close].utf8)
        guard let r = try? JSONDecoder().decode(AnalysisResult.self, from: json), !r.headline.isEmpty || !r.suggestions.isEmpty else { return nil }
        return r
    }

    static var schemaPrompt: String {
        """
        The result is shown as charts, so keep every text field very short. Reply with one JSON object and nothing else, no code fences. Shape:
        {"score": 0-100 integer for how healthy and efficient this Mac's usage looks (100 = nothing to improve),
         "scores": {"power": 0-100, "cpu": 0-100, "gpu": 0-100, "memory": 0-100, "thermal": 0-100, "battery": 0-100, "network": 0-100},
         "headline": "one short sentence, at most 25 Chinese characters or 15 English words",
         "findings": [{"title": "at most 10 Chinese characters or 6 words", "detail": "one short sentence with the key number", "severity": "high|medium|low", "category": "power|cpu|gpu|memory|thermal|battery|network", "from": "yyyy-MM-dd HH:mm", "to": "yyyy-MM-dd HH:mm"}],
         "suggestions": [{"title": "short action, at most 12 Chinese characters or 7 words", "detail": "one short sentence on how", "impact": "high|medium|low"}],
         "apps": [{"name": "app name exactly as in the data", "verdict": "expected|watch|abnormal", "note": "at most 15 Chinese characters or 8 words"}]}
        Score only the categories the data covers and leave the others out of "scores". Give "from" and "to" with times copied from the hourly table when a finding is about a specific period, and leave them out otherwise.
        Give 3-6 findings spread over the categories, 3-5 suggestions, and a verdict for each of the top apps by energy (at most 8).
        """
    }
}
