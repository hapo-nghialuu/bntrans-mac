import SwiftUI

struct SettingsView: View {
    @State private var settings = Settings.load()
    private let providerTypes = [
        "gemini", "openai", "openrouter", "groq", "ollama", "custom"
    ]
    private let langs = ["vi", "en", "ja", "ko", "zh", "fr", "de", "es"]

    var body: some View {
        Form {
            Picker("Provider", selection: $settings.providerType) {
                ForEach(providerTypes, id: \.self) { Text($0) }
            }
            if settings.providerType != "gemini" && settings.providerType != "ollama" {
                TextField("Base URL", text: $settings.baseUrl)
            }
            SecureField("API Key", text: $settings.apiKey)
            TextField("Model", text: $settings.model)
                .help("Empty = provider default")
            Picker("Target language", selection: $settings.targetLang) {
                ForEach(langs, id: \.self) { Text($0) }
            }
            Toggle("Fill translation over captured area", isOn: $settings.fillEnabled)
            HStack {
                Spacer()
                Button("Save") { settings.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
