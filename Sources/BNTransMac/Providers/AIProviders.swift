import Foundation

enum ImageMode {
    case translate, explain
}

struct Segment {
    let box: [Double] // [yMin, xMin, yMax, xMax], normalized 0-1000
    let source: String
    let translation: String
}

struct ImageResult {
    var source: String
    var translation: String
    var segments: [Segment] // empty → caller falls back to one full-region block
}

enum ProviderError: LocalizedError {
    case missingKey
    case http(Int, String)
    case textOnlyModel(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "API key is missing — set it in Settings."
        case .http(let code, let msg):
            return "API error \(code): \(msg)"
        case .textOnlyModel(let model):
            return "Model \"\(model)\" cannot read images — pick a vision-capable model in Settings."
        case .badResponse:
            return "Unexpected API response."
        }
    }
}

/// Dispatch on provider type — mirrors the extension's translate-image path.
func translateImage(
    settings: Settings,
    imageBase64: String,
    mimeType: String,
    targetLang: String,
    mode: ImageMode
) async throws -> ImageResult {
    switch settings.providerType {
    case "gemini":
        return try await geminiImageTranslate(
            apiKey: settings.apiKey,
            model: settings.effectiveModel,
            base64: imageBase64,
            mimeType: mimeType,
            targetLang: targetLang,
            mode: mode
        )
    case "claude":
        return try await claudeImageTranslate(
            apiKey: settings.apiKey,
            model: settings.effectiveModel,
            base64: imageBase64,
            mimeType: mimeType,
            targetLang: targetLang,
            mode: mode
        )
    default:
        return try await openAIImageTranslate(
            baseUrl: settings.effectiveBaseUrl,
            apiKey: settings.apiKey,
            model: settings.effectiveModel,
            base64: imageBase64,
            mimeType: mimeType,
            targetLang: targetLang,
            mode: mode
        )
    }
}

/// Text translation — selection/clipboard path (translate-text hotkey).
/// Same dispatch as translateImage: gemini and claude have their own
/// endpoint shapes, everything else uses OpenAI-compatible
/// chat/completions. Plain text in, plain text out.
func translateText(settings: Settings, text: String) async throws -> String {
    let sys = textTranslatePrompt(targetLang: settings.targetLang)
    switch settings.providerType {
    case "gemini":
        return try await geminiTextTranslate(
            apiKey: settings.apiKey,
            model: settings.effectiveModel,
            system: sys,
            text: text
        )
    case "claude":
        return try await claudeTextTranslate(
            apiKey: settings.apiKey,
            model: settings.effectiveModel,
            system: sys,
            text: text
        )
    default:
        return try await openAITextTranslate(
            baseUrl: settings.effectiveBaseUrl,
            apiKey: settings.apiKey,
            model: settings.effectiveModel,
            system: sys,
            text: text
        )
    }
}

// MARK: - Gemini (inline_data)

private func geminiImageTranslate(
    apiKey: String,
    model: String,
    base64: String,
    mimeType: String,
    targetLang: String,
    mode: ImageMode
) async throws -> ImageResult {
    guard !apiKey.isEmpty else { throw ProviderError.missingKey }
    let prompt =
        mode == .explain
        ? imageExplainPrompt(targetLang: targetLang)
        : imageOCRPrompt(targetLang: targetLang)

    var req = URLRequest(
        url: URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        )!
    )
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "contents": [
            [
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": mimeType, "data": base64]]
                ]
            ]
        ]
    ])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw httpError(http.statusCode, data, model: model)
    }
    let raw =
        (((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
    let text = (raw?.first?["text"] as? String ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    return mode == .explain
        ? ImageResult(source: "", translation: text, segments: [])
        : parseImageTranslation(text)
}

private func geminiTextTranslate(
    apiKey: String,
    model: String,
    system: String,
    text: String
) async throws -> String {
    guard !apiKey.isEmpty else { throw ProviderError.missingKey }
    var req = URLRequest(
        url: URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        )!
    )
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "system_instruction": ["parts": [["text": system]]],
        "contents": [["parts": [["text": text]]]],
    ])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw httpError(http.statusCode, data, model: model)
    }
    let raw =
        (((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
    return (raw?.first?["text"] as? String ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
}

// MARK: - OpenAI-compatible (chat/completions + image_url)

private func openAIImageTranslate(
    baseUrl: String,
    apiKey: String,
    model: String,
    base64: String,
    mimeType: String,
    targetLang: String,
    mode: ImageMode
) async throws -> ImageResult {
    let prompt =
        mode == .explain
        ? imageExplainPrompt(targetLang: targetLang)
        : imageOCRPrompt(targetLang: targetLang)

    var req = URLRequest(
        url: URL(string: "\(baseUrl.replacingOccurrences(of: "/$", with: "", options: .regularExpression))/chat/completions")!
    )
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !apiKey.isEmpty {
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": model,
        "messages": [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                    ]
                ]
            ]
        ]
    ])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw httpError(http.statusCode, data, model: model)
    }
    let choices =
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["choices"] as? [[String: Any]]
    let text =
        ((choices?.first?["message"] as? [String: Any])?["content"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return mode == .explain
        ? ImageResult(source: "", translation: text, segments: [])
        : parseImageTranslation(text)
}

private func openAITextTranslate(
    baseUrl: String,
    apiKey: String,
    model: String,
    system: String,
    text: String
) async throws -> String {
    var req = URLRequest(
        url: URL(string: "\(baseUrl.replacingOccurrences(of: "/$", with: "", options: .regularExpression))/chat/completions")!
    )
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !apiKey.isEmpty {
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": model,
        "messages": [
            ["role": "system", "content": system],
            ["role": "user", "content": text],
        ],
    ])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw httpError(http.statusCode, data, model: model)
    }
    let choices =
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["choices"] as? [[String: Any]]
    return ((choices?.first?["message"] as? [String: Any])?["content"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Claude (Anthropic Messages API)

private func claudeImageTranslate(
    apiKey: String,
    model: String,
    base64: String,
    mimeType: String,
    targetLang: String,
    mode: ImageMode
) async throws -> ImageResult {
    guard !apiKey.isEmpty else { throw ProviderError.missingKey }
    let prompt =
        mode == .explain
        ? imageExplainPrompt(targetLang: targetLang)
        : imageOCRPrompt(targetLang: targetLang)

    var req = URLRequest(
        url: URL(string: "https://api.anthropic.com/v1/messages")!
    )
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": model,
        "max_tokens": 4096,
        "messages": [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": mimeType,
                            "data": base64,
                        ],
                    ],
                ],
            ]
        ],
    ])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw httpError(http.statusCode, data, model: model)
    }
    let blocks =
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["content"] as? [[String: Any]]
    let text = (blocks ?? [])
        .filter { $0["type"] as? String == "text" }
        .compactMap { $0["text"] as? String }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return mode == .explain
        ? ImageResult(source: "", translation: text, segments: [])
        : parseImageTranslation(text)
}

private func claudeTextTranslate(
    apiKey: String,
    model: String,
    system: String,
    text: String
) async throws -> String {
    guard !apiKey.isEmpty else { throw ProviderError.missingKey }
    var req = URLRequest(
        url: URL(string: "https://api.anthropic.com/v1/messages")!
    )
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    req.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": model,
        "max_tokens": 4096,
        "system": system,
        "messages": [["role": "user", "content": text]],
    ])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw httpError(http.statusCode, data, model: model)
    }
    let blocks =
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["content"] as? [[String: Any]]
    return (blocks ?? [])
        .filter { $0["type"] as? String == "text" }
        .compactMap { $0["text"] as? String }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Shared helpers

private func httpError(_ code: Int, _ data: Data, model: String) -> Error {
    let msg =
        (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
        ?? "HTTP \(code)"
    if msg.range(
        of: "must be a string|does not support image|multimodal|vision",
        options: .regularExpression
    ) != nil {
        return ProviderError.textOnlyModel(model)
    }
    return ProviderError.http(code, msg)
}

/// Same parser as the extension: strict-JSON segments first, then the
/// legacy <<<SOURCE>>> format, then whole-reply fallback.
private func parseImageTranslation(_ raw: String) -> ImageResult {
    let cleaned = raw.replacingOccurrences(
        of: "```(?:json)?",
        with: "",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    if let data = cleaned.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let segs = obj["segments"] as? [[String: Any]]
    {
        let valid = segs.compactMap { s -> Segment? in
            guard let box = s["box"] as? [Double], box.count == 4,
                let tr = s["translation"] as? String
            else { return nil }
            return Segment(
                box: box,
                source: s["source"] as? String ?? "",
                translation: tr
            )
        }
        return ImageResult(
            source: segs.compactMap { $0["source"] as? String }.joined(
                separator: "\n"
            ),
            translation: segs.compactMap { $0["translation"] as? String }
                .joined(separator: "\n"),
            segments: valid
        )
    }
    if let m = raw.range(
        of: "<<<SOURCE>>>\\s*([\\s\\S]*?)\\s*<<<TRANSLATION>>>\\s*([\\s\\S]*?)\\s*$",
        options: [.regularExpression]
    ) {
        let parts = raw[m].components(separatedBy: "<<<TRANSLATION>>>")
        return ImageResult(
            source: String(parts[0].dropFirst("<<<SOURCE>>>".count))
                .trimmingCharacters(in: .whitespacesAndNewlines),
            translation: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : "",
            segments: []
        )
    }
    return ImageResult(source: "", translation: raw, segments: [])
}
