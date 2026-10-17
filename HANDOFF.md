# Handoff — BNTrans macOS app (bntrans-mac)

> Snapshot cuối session ngày 2026-10-15. Paste file này vào session mới để tiếp tục.

## Repo & trạng thái

- **Repo**: `/Users/nghialuutrung/Desktop/bntrans-mac` — SwiftPM executable.
  Remote: `git@github.com:hapo-nghialuu/bntrans-mac.git` (public). Head: `e416adf`
- **Extension** (repo riêng, reference only): `/Users/nghialuutrung/Desktop/bntrans-exention`
- **Chạy app**: `cd ~/Desktop/bntrans-mac && swift run` (hoặc `./.build/debug/BNTransMac`). Build: `swift build`, 0 warning

## Kiến trúc hiện tại

```
⇧⌘S (Carbon hotkey, configurable) → RegionSelector (dim + viền xanh + badge W×H)
→ ScreenCaptureKit crop → JPEG ≤1280 → provider vision OCR+translate
→ FillOverlay: veil mỏng toàn vùng + segment plates (sample màu, 0.85 alpha)
+ icon toolbar pill compact (globe/lightbulb/copy/xmark)
```

- `Providers/AIProviders.swift` — dispatch theo `providerType`: gemini | openai-compatible (openai/openrouter/groq/ollama/custom) | **claude** (Anthropic Messages API, x-api-key + anthropic-version, image base64 blocks)
- `Providers/Models.swift` — `ModelsFetcher.fetch` per-provider (Gemini /v1beta, Anthropic /v1/models, OpenAI-compat {base}/models); `--dump-models` debug flag
- `UI/Theme.swift` — BTTheme tokens + `BTFont` (bundled IBM Plex — lookup đúng **PS name** `IBMPlex*-Medm/SmBld`, register lúc launch)
- `UI/SettingsView.swift` — sidebar 4 tab, auto-save UserDefaults; Provider tab có live model picker
- `Capture/RegionSelector.swift` — SelectionView: dim, punch hole, viền xanh, hint + badge **NSTextField** (không NSStringDrawing — từng crash)
- `Overlay/FillOverlay.swift` — `show()`: guard rỗng sớm → veil `averageColor` toàn ảnh @0.85 → segment plates (grow tỉ lệ thiên phải, grow xuống khi chữ wrap dư, fit font floor 9pt)

## Debug hooks (trong binary)

```sh
./.build/debug/BNTransMac --dump-models        # list model theo settings đã lưu
./.build/debug/BNTransMac --open-settings      # mở Settings khi launch
./.build/debug/BNTransMac --open-settings --open-select
```

Log: stderr → `> /tmp/bntrans.log 2>&1`. Có `NSLog [BTFill]` mỗi lần `FillOverlay.show` (mode/segments/translationLen/first80).

## Đã fix xong (tham chiếu nếu tái phát)

- **Crash `sizeWithAttributes`** trong badge → đổi sang NSTextField
- **Khối đen không chữ** → provider thực ra trả data; guard khi segments+translation đều rỗng
- **Box fill trắng bất thường** → `interpolationQuality .low` nearest-sample trúng glyph trắng; đổi `.high`
- **Chữ gốc lòi mép phải** → provider box hẹp hơn glyph; inflate tỉ lệ, thiên phải
- **Font Plex không load** → PS name khác tên file (`-Medm` không phải `-Medium`)

## Settings storage

`UserDefaults` key `bntrans.settings`: providerType, apiKey, baseUrl, model,
targetLang, fillEnabled, appearance, hotkeyKeyCode, hotkeyModifiers.
Auto-save; notification `.bntransSettingsChanged` re-apply appearance + hotkey.

## Việc còn lại / hướng tiếp

1. **Verify E2E**: provider Claude (key console.anthropic.com/settings/keys) + veil/fill/badge trên capture thật nhiều lần
2. `.app` bundle + icon + notarization nếu phát hành
3. Feature parity với extension nếu muốn (hover-translate, history…)

## Nhạy cảm

API keys đã dùng để test — trong UserDefaults app + Brave extension storage, **không commit, không in ra**.

## Style rules

- Tiếng Việt, gọi "bro"; conventional commits, tách theo task; không AI attribution trong code
- Không bịa proof — verify bằng build + window list + screenshot (`screencapture -R` / `-l <windowId>`)
