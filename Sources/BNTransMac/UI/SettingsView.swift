import AppKit
import SwiftUI

// MARK: - Instrument layout primitives (ported from BirdNion
// SettingsSceneRoot: SettingsPage / SettingsCard / SettingsLabeledRow)

/// Scrollable settings page — stack of section groups on paper background.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BTTheme.background)
    }
}

/// Section group: uppercase eyebrow + hairline-divided rows (no filled card).
private struct SettingsCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .plexEyebrow()
                    .padding(.top, 22)
                    .padding(.bottom, 4)
            }
            VStack(spacing: 0) { content() }
        }
    }
}

/// Pane title + subtitle, closed by the strong ink rule
/// (`SettingsPaneHeader` in BirdNion).
private struct SettingsPaneHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.plexSans(22, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(BTTheme.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.plexSans(13))
                    .foregroundStyle(BTTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .inkRuleBottom()
        .padding(.bottom, 4)
    }
}

/// Title + optional subtitle + trailing control in a fixed-width column;
/// top hairline separates rows.
private struct SettingsLabeledRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.plexSans(14, weight: .medium))
                    .foregroundStyle(BTTheme.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.plexSans(12))
                        .foregroundStyle(BTTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
                .font(.plexSans(12))
                .frame(width: 160, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
        .contentShape(Rectangle())
        .hairlineTop(BTTheme.hairline)
    }
}

/// Full-width field row variant — label block on top, control spans the row.
private struct SettingsFieldRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let field: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.plexSans(14, weight: .medium))
                    .foregroundStyle(BTTheme.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.plexSans(12))
                        .foregroundStyle(BTTheme.secondary)
                }
            }
            field()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineTop(BTTheme.hairline)
    }
}

/// Sets the NSWindow background to Instrument paper/ink so AppKit clears to
/// the right color during live resize.
private struct SettingsWindowAppearanceView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.appearance = nil
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 23 / 255, green: 23 / 255, blue: 15 / 255, alpha: 1)
                : NSColor(srgbRed: 251 / 255, green: 250 / 255, blue: 247 / 255, alpha: 1)
        }
    }
}

// MARK: - Tabs

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, provider, capture, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .provider: return "Provider"
        case .capture: return "Capture"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .provider: return "bolt.horizontal"
        case .capture: return "camera.viewfinder"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Sidebar

/// Left nav column — `group` surface, right border, nav rows with ink-fill
/// selected state, pinned version footer (BirdNion SettingsSidebar, minus
/// search/roster which this app does not need).
private struct SettingsSidebar: View {
    @Binding var selected: SettingsTab
    @State private var hovering: SettingsTab?

    var body: some View {
        VStack(spacing: 0) {
            // Brand header — logo + wordmark instead of BirdNion's search box.
            HStack(spacing: 9) {
                if let img = Self.icon(named: "icon-128") {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("BNTrans")
                    .font(.plexSans(13, weight: .semibold))
                    .foregroundStyle(BTTheme.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { BTTheme.hairline.frame(height: 1) }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        navRow(tab)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Pinned footer.
            Text("BNTrans DEV")
                .font(.plexMono(10))
                .tracking(0.6)
                .foregroundStyle(BTTheme.tertiary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .overlay(alignment: .top) { BTTheme.hairline.frame(height: 1) }
        }
        .frame(width: 190)
        .background(BTTheme.group)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(BTTheme.border)
                .frame(width: 1)
        }
    }

    private func navRow(_ tab: SettingsTab) -> some View {
        let isSelected = tab == selected
        let isHovering = hovering == tab

        return Button {
            selected = tab
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? BTTheme.background : BTTheme.secondary)
                    .frame(width: 14, height: 14)
                Text(tab.title)
                    .font(.plexSans(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? BTTheme.background : BTTheme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .fill(isSelected
                          ? BTTheme.primary
                          : (isHovering ? BTTheme.hoverSurface : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside ? tab : (hovering == tab ? nil : hovering)
        }
        .pointingHandCursor()
    }

    static func icon(named name: String) -> NSImage? {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "png",
                subdirectory: "Resources/Icons"
            ) ?? Bundle.module.url(forResource: name, withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @Binding var settings: Settings

    var body: some View {
        SettingsPage {
            SettingsPaneHeader(
                title: "General",
                subtitle: "App appearance and shortcuts"
            )

            SettingsCard(header: "App") {
                SettingsLabeledRow(
                    title: "Appearance",
                    subtitle: "Light, dark, or follow macOS"
                ) {
                    InstrumentMenuSelect(
                        options: AppAppearance.allCases.map {
                            ($0.rawValue, $0.title)
                        },
                        selection: $settings.appearance
                    )
                    .onChange(of: settings.appearance) { _, value in
                        AppAppearance.apply(value)
                    }
                }
            }

            SettingsCard(header: "Shortcut") {
                SettingsLabeledRow(
                    title: "Capture area",
                    subtitle: "Click to record a new global hotkey"
                ) {
                    HotkeyRecorder(
                        keyCode: $settings.hotkeyKeyCode,
                        modifiers: $settings.hotkeyModifiers
                    )
                }
            }
        }
    }
}

private struct ProviderPane: View {
    @Binding var settings: Settings

    /// `--open-select` opens Settings straight to this pane with the model
    /// select force-opened — exercises the real ScrollView hierarchy.
    private static let debugOpenSelect =
        CommandLine.arguments.contains("--open-select")

    @State private var models: [String] = []
    @State private var modelsLoading = false
    @State private var modelsError: String?
    @State private var customModel = false

    private let providerTypes = [
        "gemini", "openai", "openrouter", "groq", "ollama", "custom"
    ]
    private static let customValue = "__custom__"

    private var usesBaseURL: Bool {
        settings.providerType != "gemini" && settings.providerType != "ollama"
    }

    private var keySubtitle: String {
        settings.providerType == "ollama"
            ? "Optional for local Ollama" : "Stored locally in UserDefaults"
    }

    var body: some View {
        SettingsPage {
            SettingsPaneHeader(
                title: "Provider",
                subtitle: "AI service for screenshot OCR and translation"
            )

            SettingsCard(header: "Connection") {
                SettingsLabeledRow(
                    title: "Provider",
                    subtitle: "Which AI service reads the captured image"
                ) {
                    InstrumentMenuSelect(
                        options: providerTypes.map { ($0, providerTitle($0)) },
                        selection: $settings.providerType
                    )
                }

                if usesBaseURL {
                    SettingsFieldRow(
                        title: "Base URL",
                        subtitle: "Leave empty for the provider default"
                    ) {
                        TextField(
                            "",
                            text: $settings.baseUrl,
                            prompt: Text(settings.effectiveBaseUrl)
                                .foregroundStyle(BTTheme.tertiary)
                        )
                        .font(.plexMono(12))
                        .instrumentControlFieldStyle()
                    }
                }

                SettingsFieldRow(
                    title: "API key",
                    subtitle: keySubtitle
                ) {
                    SecureField(
                        "",
                        text: $settings.apiKey,
                        prompt: Text("Paste key…").foregroundStyle(BTTheme.tertiary)
                    )
                    .font(.plexMono(12))
                    .instrumentControlFieldStyle()
                }
            }

            SettingsCard(header: "Model") {
                SettingsFieldRow(
                    title: "Model",
                    subtitle: "Vision-capable model. Empty uses the provider default"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            InstrumentMenuSelect(
                                options: modelOptions,
                                selection: modelSelection,
                                debugOpen: Self.debugOpenSelect
                            )
                            refreshButton
                        }
                        if customModel {
                            TextField(
                                "",
                                text: $settings.model,
                                prompt: Text("model-id")
                                    .foregroundStyle(BTTheme.tertiary)
                            )
                            .font(.plexMono(12))
                            .instrumentControlFieldStyle()
                        }
                        hint
                    }
                }
            }
        }
        .task { await refreshModels() }
        .onChange(of: settings.providerType) { _, _ in
            models = []
            modelsError = nil
            Task { await refreshModels() }
        }
    }

    /// Auto + fetched list + saved model (tagged when it is not on the
    /// provider's list) + manual entry — same shape as the extension's
    /// screenshot model select.
    private var modelOptions: [(String, String)] {
        var out: [(String, String)] = [
            ("", "Auto — \(settings.effectiveModel)")
        ]
        let suggested = ModelsFetcher.suggested[settings.providerType] ?? []
        for m in models {
            let tag = suggested.contains(m) ? "  ·  suggested" : ""
            out.append((m, "\(m)\(tag)"))
        }
        if !settings.model.isEmpty, !models.contains(settings.model) {
            let tag = models.isEmpty ? "" : "  ·  not in provider list"
            out.append((settings.model, "\(settings.model)\(tag)"))
        }
        out.append((Self.customValue, "Enter model manually…"))
        return out
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { customModel ? Self.customValue : settings.model },
            set: { value in
                if value == Self.customValue {
                    customModel = true
                } else {
                    customModel = false
                    settings.model = value
                }
            }
        )
    }

    private var refreshButton: some View {
        Button {
            Task { await refreshModels() }
        } label: {
            Group {
                if modelsLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BTTheme.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .background(BTTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .strokeBorder(BTTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(modelsLoading)
        .help("Reload the provider's model list")
    }

    @ViewBuilder private var hint: some View {
        if modelsLoading {
            Text("Loading models…")
                .font(.plexSans(11))
                .foregroundStyle(BTTheme.tertiary)
        } else if let modelsError {
            Text("⚠ \(modelsError)")
                .font(.plexSans(11))
                .foregroundStyle(BTTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if !models.isEmpty {
            Text(
                "\(models.count) models — "
                    + models.prefix(3).joined(separator: ", ")
                    + (models.count > 3 ? "…" : "")
            )
            .font(.plexSans(11))
            .foregroundStyle(BTTheme.tertiary)
        }
    }

    @MainActor
    private func refreshModels() async {
        modelsLoading = true
        modelsError = nil
        do {
            models = try await ModelsFetcher.fetch(settings: settings)
        } catch {
            models = []
            modelsError = error.localizedDescription
        }
        modelsLoading = false
    }

    private func providerTitle(_ id: String) -> String {
        switch id {
        case "openrouter": return "OpenRouter"
        case "groq": return "Groq"
        case "openai": return "OpenAI"
        case "ollama": return "Ollama"
        case "gemini": return "Gemini"
        case "custom": return "Custom"
        default: return id
        }
    }
}

/// Standalone harness for `--test-select`: renders the model select with a
/// realistic option list and opens the panel without needing a click.
struct SelectTestView: View {
    @State private var selection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MODEL").plexEyebrow()
            InstrumentMenuSelect(
                options: [
                    ("", "Auto — gemini-3.1-flash-lite"),
                    ("gemini-3.1-flash-lite", "gemini-3.1-flash-lite  ·  suggested"),
                    ("gemini-2.5-flash", "gemini-2.5-flash  ·  suggested"),
                    ("gemini-2.5-pro", "gemini-2.5-pro"),
                    ("__custom__", "Enter model manually…"),
                ],
                selection: $selection,
                debugOpen: true
            )
        }
        .padding(24)
        .frame(width: 372, alignment: .leading)
        .background(BTTheme.background)
    }
}

private struct CapturePane: View {
    @Binding var settings: Settings

    private let langs = ["vi", "en", "ja", "ko", "zh", "fr", "de", "es"]

    var body: some View {
        SettingsPage {
            SettingsPaneHeader(
                title: "Capture",
                subtitle: "Screenshot selection and overlay behavior"
            )

            SettingsCard(header: "Translate") {
                SettingsLabeledRow(
                    title: "Target language",
                    subtitle: "Language to translate detected text into"
                ) {
                    InstrumentMenuSelect(
                        options: langs.map { ($0, $0) },
                        selection: $settings.targetLang
                    )
                }

                SettingsLabeledRow(
                    title: "Fill overlay",
                    subtitle: "Draw the translation over the captured area"
                ) {
                    Toggle("", isOn: $settings.fillEnabled)
                        .labelsHidden()
                        .toggleStyle(.instrumentSwitch)
                }
            }

        }
    }
}

private struct AboutPane: View {
    var body: some View {
        SettingsPage {
            SettingsPaneHeader(
                title: "About",
                subtitle: "BNTrans for macOS"
            )

            SettingsCard(header: "App") {
                SettingsLabeledRow(
                    title: "BNTrans",
                    subtitle: "Native port of the BNTrans Chrome extension"
                ) {
                    if let img = SettingsSidebar.icon(named: "icon-128") {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                SettingsLabeledRow(
                    title: "Version",
                    subtitle: "Development build"
                ) {
                    Text("dev")
                        .font(.plexMono(11))
                        .foregroundStyle(BTTheme.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Quit BNTrans") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.instrumentOutline)
            }
            .padding(.top, 18)
            .hairlineTop(BTTheme.hairline)
        }
    }
}

// MARK: - Root

/// Instrument-style settings window: left nav sidebar + right scrollable
/// pane — the BirdNion Settings architecture scaled down to this app's
/// three panes.
struct SettingsView: View {
    @State private var settings = Settings.load()
    @State private var tab: SettingsTab =
        CommandLine.arguments.contains("--open-select")
            || CommandLine.arguments.contains("--click-select")
        ? .provider : .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selected: $tab)

            VStack(spacing: 0) {
                pane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BTTheme.background)
        }
        .frame(width: 720, height: 560)
        .overlay(SettingsWindowAppearanceView().frame(width: 0, height: 0))
        .tint(BTTheme.accent)
        // Auto-save — System Settings style: every change persists and
        // re-applies (theme, hotkey) immediately via .bntransSettingsChanged.
        .onChange(of: settings) { _, value in
            value.save()
        }
    }

    @ViewBuilder private var pane: some View {
        switch tab {
        case .general: GeneralPane(settings: $settings)
        case .provider: ProviderPane(settings: $settings)
        case .capture: CapturePane(settings: $settings)
        case .about: AboutPane()
        }
    }
}
