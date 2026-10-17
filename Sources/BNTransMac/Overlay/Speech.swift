import AVFoundation

/// Shared text-to-speech for the overlay and the text-result panel — one
/// synthesizer so a new speak() replaces whatever is currently playing.
@MainActor
enum BTSpeech {
    private static let synth = AVSpeechSynthesizer()

    static var isSpeaking: Bool { synth.isSpeaking }

    static func toggle(_ text: String, lang: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        } else {
            speak(text, lang: lang)
        }
    }

    static func speak(_ text: String, lang: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: voiceLang(lang))
        synth.speak(u)
    }

    static func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    /// "vi" -> "vi-VN" — AVSpeechSynthesisVoice wants a BCP-47 locale; bare
    /// ISO codes map to their canonical region.
    private static func voiceLang(_ code: String) -> String {
        if code.contains("-") { return code }
        let map = [
            "vi": "vi-VN", "en": "en-US", "ja": "ja-JP", "ko": "ko-KR",
            "zh": "zh-CN", "fr": "fr-FR", "de": "de-DE", "es": "es-ES",
            "th": "th-TH", "id": "id-ID", "ru": "ru-RU", "pt": "pt-BR",
            "it": "it-IT", "nl": "nl-NL", "hi": "hi-IN", "ar": "ar-SA",
        ]
        return map[code] ?? "en-US"
    }
}
