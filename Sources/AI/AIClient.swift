import Foundation

enum AIProvider: String, CaseIterable {
    case anthropic, openai

    var title: String { self == .anthropic ? "Claude (Anthropic)" : L("OpenAI 兼容接口", "OpenAI-compatible") }
}

struct AIRequest {
    var provider: AIProvider
    var model: String
    var key: String
    var baseURL: String
    var system: String
    var prompt: String
}

enum AIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

enum AIClient {
    static let claudeModels = [("claude-opus-5-5", "Claude Opus 5.5"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"), ("claude-haiku-5-5", "Claude Haiku 5.5")]
    static let defaultClaudeModel = "claude-opus-5-5"
    static let defaultOpenAIBase = "https://api.openai.com/v1"

    private static let claudeEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let claudeVersion = "2026-10-21"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    private static let modelsWithFallback: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]
    private static let maxTokens = 16000
    private static let timeout: TimeInterval = 600

    @discardableResult
    static func send(_ r: AIRequest, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        let request: URLRequest
        do { request = try r.provider == .anthropic ? claudeRequest(r) : openAIRequest(r) } catch { completion(.failure(error)); return nil }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            guard (200..<300).contains(status) else {
                let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? data.map { String(decoding: $0.prefix(400), as: UTF8.self) } ?? ""
                completion(.failure(AIError.message("HTTP \(status): \(detail)")))
                return
            }
            completion(r.provider == .anthropic ? parseClaude(json) : parseOpenAI(json))
        }
        task.resume()
        return task
    }

    private static func claudeRequest(_ r: AIRequest) throws -> URLRequest {
        var req = URLRequest(url: claudeEndpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(r.key, forHTTPHeaderField: "x-api-key")
        req.setValue(claudeVersion, forHTTPHeaderField: "anthropic-version")
        var body: [String: Any] = [
            "model": r.model, "max_tokens": maxTokens, "system": r.system,
            "messages": [["role": "user", "content": r.prompt]],
            "output_config": ["effort": "medium"],
        ]
        if modelsWithFallback.contains(r.model) {
            req.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func openAIRequest(_ r: AIRequest) throws -> URLRequest {
        let trimmed = r.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let base = trimmed.isEmpty ? defaultOpenAIBase : trimmed
        guard let url = URL(string: base + "/chat/completions"), url.scheme != nil else {
            throw AIError.message(L("Base URL 无效", "Invalid base URL"))
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !r.key.isEmpty { req.setValue("Bearer \(r.key)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["model": r.model, "messages": [["role": "system", "content": r.system], ["role": "user", "content": r.prompt]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func parseClaude(_ json: [String: Any]) -> Result<String, Error> {
        if json["stop_reason"] as? String == "refusal" {
            return .failure(AIError.message(L("模型拒绝了这次请求，换个模型再试", "The model declined this request; try another model")))
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? .failure(AIError.message(L("没有收到分析结果", "No analysis returned"))) : .success(text)
    }

    private static func parseOpenAI(_ json: [String: Any]) -> Result<String, Error> {
        let message = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
        let text = message?["content"] as? String ?? ""
        return text.isEmpty ? .failure(AIError.message(L("没有收到分析结果", "No analysis returned"))) : .success(text)
    }
}
