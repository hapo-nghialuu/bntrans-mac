import Foundation

/// Fetches the live model list for the configured provider — same endpoints
/// as the extension's `fetchProviderModels` (Gemini `models?key=`,
/// OpenAI-compatible `GET {base}/models` with Bearer).
enum ModelsFetcher {
    struct FetchError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Vision-capable models to surface first per provider type — same
    /// curated lists the extension tags "· suggested".
    static let suggested: [String: [String]] = [
        "gemini": ["gemini-3.1-flash-lite", "gemini-2.5-flash"],
        "openai": ["gpt-4o-mini", "gpt-4o"],
        "openrouter": ["google/gemini-3.1-flash-lite", "openai/gpt-4o-mini",
                       "google/gemini-2.5-flash"],
        "groq": ["qwen/qwen3.8-27b"],
        "claude": ["claude-haiku-5-5", "claude-sonnet-5-5"],
    ]

    static func fetch(settings: Settings) async throws -> [String] {
        if settings.providerType == "gemini" {
            return try await fetchGemini(apiKey: settings.apiKey)
        }
        if settings.providerType == "claude" {
            return try await fetchClaude(apiKey: settings.apiKey)
        }
        return try await fetchOpenAICompatible(settings: settings)
    }

    private static func fetchGemini(apiKey: String) async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw FetchError(message: "Enter an API key first")
        }
        var comps = URLComponents(
            string:
                "https://generativelanguage.googleapis.com/v1beta/models")!
        comps.queryItems = [URLQueryItem(name: "key", value: key)]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        try ensureOK(resp, data)
        struct R: Decodable {
            struct M: Decodable {
                let name: String
                let supportedGenerationMethods: [String]?
            }
            let models: [M]?
        }
        // Same filter as the extension: chat-capable Gemini/Gemma only —
        // drops TTS, image, video (veo), robotics, embeddings, aqa…
        let junk =
            /(tts|image|robotics|omni|transcribe|computer-use|lyria|customtools|aqa|embedding|learnlm|bidi|veo)/
        return (try JSONDecoder().decode(R.self, from: data).models ?? [])
            .filter {
                $0.supportedGenerationMethods?.contains("generateContent")
                    ?? false
            }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter {
                $0.firstMatch(of: /^(gemini|gemma)/) != nil
                    && $0.firstMatch(of: junk) == nil
            }
    }

    /// Anthropic `/v1/models` — same call as the extension minus the
    /// browser-access header (native app, no CORS). Every claude-* model
    /// is chat + vision capable, so the list needs no filter.
    private static func fetchClaude(apiKey: String) async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw FetchError(message: "Enter an API key first")
        }
        var req = URLRequest(
            url: URL(
                string: "https://api.anthropic.com/v1/models?limit=100")!
        )
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp, data)
        struct R: Decodable {
            struct M: Decodable { let id: String }
            let data: [M]?
        }
        return (try JSONDecoder().decode(R.self, from: data).data ?? [])
            .map(\.id)
    }

    private static func fetchOpenAICompatible(settings: Settings) async throws
        -> [String]
    {
        let base = settings.effectiveBaseUrl
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            throw FetchError(message: "Enter a base URL first")
        }
        guard
            let url = URL(
                string: base
                    .replacingOccurrences(of: "/+$", with: "",
                                          options: .regularExpression)
                    + "/models")
        else { throw FetchError(message: "Invalid base URL") }
        var req = URLRequest(url: url)
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp, data)
        struct R: Decodable {
            struct M: Decodable { let id: String }
            let data: [M]?
        }
        // Same filter as the extension — drops non-chat audio/image/
        // embedding/moderation models.
        return (try JSONDecoder().decode(R.self, from: data).data ?? [])
            .map(\.id)
            .filter {
                !$0.isEmpty
                    && $0.range(
                        of: "(tts|whisper|dall-e|embedding|moderation|audio|realtime|transcribe|image)",
                        options: [.regularExpression, .caseInsensitive]
                    ) == nil
            }
    }

    private static func ensureOK(_ resp: URLResponse, _ data: Data) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            struct E: Decodable {
                struct Inner: Decodable { let message: String? }
                let error: Inner?
                let message: String?
            }
            let detail =
                (try? JSONDecoder().decode(E.self, from: data))?
                .error?.message
                ?? (try? JSONDecoder().decode(E.self, from: data))?.message
                ?? String(data: data.prefix(300), encoding: .utf8)
                ?? "HTTP \(code)"
            throw FetchError(message: detail)
        }
    }
}
