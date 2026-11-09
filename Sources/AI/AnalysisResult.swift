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
    var id: String { title + detail }
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

    enum CodingKeys: String, CodingKey { case score, headline, findings, suggestions, apps }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = min(max((try? c.decode(Int.self, forKey: .score)) ?? Int((try? c.decode(Double.self, forKey: .score)) ?? 50), 0), 100)
        headline = (try? c.decode(String.self, forKey: .headline)) ?? ""
        findings = (try? c.decode([Finding].self, forKey: .findings)) ?? []
        suggestions = ((try? c.decode([Suggestion].self, forKey: .suggestions)) ?? []).sorted { $0.impact < $1.impact }
        apps = (try? c.decode([AppVerdict].self, forKey: .apps)) ?? []
    }

    static func parse(_ text: String) -> AnalysisResult? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        let json = Data(text[open...close].utf8)
        guard let r = try? JSONDecoder().decode(AnalysisResult.self, from: json), !r.headline.isEmpty || !r.suggestions.isEmpty else { return nil }
        return r
    }

    static var schemaPrompt: String {
        """
        Reply with one JSON object and nothing else, no code fences. Shape:
        {"score": 0-100 integer for how healthy and efficient this Mac's usage looks (100 = nothing to improve),
         "headline": "one sentence summary",
         "findings": [{"title": "short", "detail": "one or two sentences citing numbers", "severity": "high|medium|low", "category": "power|cpu|gpu|memory|thermal|battery|network"}],
         "suggestions": [{"title": "short action", "detail": "why and how, one or two sentences", "impact": "high|medium|low"}],
         "apps": [{"name": "app name exactly as in the data", "verdict": "expected|watch|abnormal", "note": "one short sentence"}]}
        Give 3-8 findings spread over the categories the data supports, 3-6 suggestions, and a verdict for each of the top apps by energy (at most 8).
        """
    }
}
