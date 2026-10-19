# BNTrans Mac

Menu-bar macOS app — the BNTrans extension's screenshot-translate feature,
native. Select a screen region → OCR + translate via a vision AI provider →
translation painted over the captured area.

## Features

- **⇧⌘S** global hotkey (Carbon `RegisterEventHotKey`, no Accessibility perm)
- **⇧⌘T** translates the current selection (Accessibility) or clipboard
  fallback into a floating result panel
- Region drag-select overlay on all screens, Esc cancels
- ScreenCaptureKit capture → crop → downscale to ≤1280px JPEG (fast detect)
- Providers: Gemini (inline_data) and OpenAI-compatible `chat/completions`
  (OpenAI / OpenRouter / Groq / Ollama / custom)
- Fill overlay: per-segment opaque boxes on the original text or a
  scrollable explanation card, plus copy/speech/recapture controls
- Alert popup fallback with Copy when fill is off

## Build & run

```sh
swift build
swift run            # debug
# or release:
swift run -c release
```

First capture prompts macOS for **Screen Recording** permission
(System Settings → Privacy & Security → Screen Recording → enable the app,
then restart it).

## Settings

Menu-bar icon → Settings… — provider, API key, model, target language,
fill toggle, and both global shortcuts. Saved to UserDefaults. Leave Model
empty for the per-provider vision default (gemini-3.1-flash-lite, gpt-4o-mini, qwen/qwen3.8-27b…).

## Layout

```
Sources/BNTransMac/
  main.swift                 NSApplication + accessory (menu-bar) mode
  App/AppDelegate.swift      status item, Carbon hotkey, capture pipeline
  Capture/RegionSelector.swift  per-screen drag overlay → CGRect
  Capture/ScreenShotter.swift   ScreenCaptureKit capture + pixel-accurate crop
  Overlay/FillOverlay.swift     borderless overlay: pill bar + segment views
  Overlay/TextResultPanel.swift floating text translation result card
  Providers/Prompts.swift       OCR/explain prompts (ported from the extension)
  Providers/AIProviders.swift   translateImage for Gemini + OpenAI-compatible
  Settings/Settings.swift       UserDefaults config
  UI/SettingsView.swift         SwiftUI settings form
```

## Not yet

- Launch at login and recent-translation history
- Target-language picker on the overlay
- .app bundle + notarization for distribution
