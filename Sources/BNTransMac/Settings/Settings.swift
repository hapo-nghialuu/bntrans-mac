import Foundation

/// UserDefaults-backed settings — same shape as the extension's provider
/// config so users can reuse the same keys/models.
struct Settings: Equatable {
    var providerType: String = "gemini" // gemini | openai | openrouter | groq | claude | ollama | custom
    var apiKey: String = ""
    var baseUrl: String = ""
    var model: String = "" // empty = provider default
    var targetLang: String = "vi"
    var fillEnabled: Bool = true
    var appearance: String = "auto" // light | dark | auto
    /// Capture hotkey: virtual keyCode + Carbon modifier flags (cmdKey 0x100,
    /// shiftKey 0x200, optionKey 0x800, controlKey 0x1000). Default ⇧⌘S.
    var hotkeyKeyCode: Int = 1 // kVK_ANSI_S
    var hotkeyModifiers: Int = 768 // cmdKey | shiftKey

    private static let key = "bntrans.settings"

    static func load() -> Settings {
        guard let d = UserDefaults.standard.dictionary(forKey: key) else {
            return Settings()
        }
        return Settings(
            providerType: d["providerType"] as? String ?? "gemini",
            apiKey: d["apiKey"] as? String ?? "",
            baseUrl: d["baseUrl"] as? String ?? "",
            model: d["model"] as? String ?? "",
            targetLang: d["targetLang"] as? String ?? "vi",
            fillEnabled: d["fillEnabled"] as? Bool ?? true,
            appearance: d["appearance"] as? String ?? "auto",
            hotkeyKeyCode: d["hotkeyKeyCode"] as? Int ?? 1,
            hotkeyModifiers: d["hotkeyModifiers"] as? Int ?? 768
        )
    }

    func save() {
        UserDefaults.standard.set(
            [
                "providerType": providerType,
                "apiKey": apiKey,
                "baseUrl": baseUrl,
                "model": model,
                "targetLang": targetLang,
                "fillEnabled": fillEnabled,
                "appearance": appearance,
                "hotkeyKeyCode": hotkeyKeyCode,
                "hotkeyModifiers": hotkeyModifiers
            ],
            forKey: Settings.key
        )
        NotificationCenter.default.post(
            name: .bntransSettingsChanged, object: nil)
    }

    var effectiveModel: String {
        if !model.isEmpty { return model }
        switch providerType {
        case "gemini": return "gemini-3.1-flash-lite"
        case "openai": return "gpt-4o-mini"
        case "openrouter": return "openai/gpt-4o-mini"
        case "groq": return "qwen/qwen3.8-27b" // only Groq vision model left
        case "claude": return "claude-haiku-5-5"
        case "ollama": return "llava"
        default: return model
        }
    }

    var effectiveBaseUrl: String {
        if !baseUrl.isEmpty { return baseUrl }
        switch providerType {
        case "openai": return "https://api.openai.com/v1"
        case "openrouter": return "https://openrouter.ai/api/v1"
        case "groq": return "https://api.groq.com/openai/v1"
        case "ollama": return "http://localhost:11434/v1"
        default: return baseUrl
        }
    }
}

extension Notification.Name {
    /// Posted by `Settings.save()` so the AppDelegate can re-apply the
    /// global hotkey and appearance without polling.
    static let bntransSettingsChanged = Notification.Name("bntrans.settingsChanged")
}
