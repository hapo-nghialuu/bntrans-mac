# Handoff — BNTrans macOS app (bntrans-mac)

> Snapshot 2026-10-15 — **đang ở giữa một "polish pass" lớn, chưa hoàn thành**.
> Paste file này vào session mới (local hoặc Devin Cloud) để tiếp tục.

## Repo & trạng thái

- **Repo**: `git@github.com:hapo-nghialuu/bntrans-mac.git` (public), branch `main`.
  Local: `/Users/nghialuutrung/Desktop/bntrans-mac` — SwiftPM executable.
- **Extension** (repo riêng, reference only, KHÔNG dùng lại code):
  `/Users/nghialuutrung/Desktop/bntrans-exention`
- **Chạy**: `swift build` (đang 0 warning) → `./.build/debug/BNTransMac > /tmp/bntrans.log 2>&1 &`

## ⚠️ WIP — "polish pass" đang làm dở (đọc kỹ trước khi sửa)

Đợt feature/fix lớn được duyệt "làm toàn bộ" gồm: explain card, Esc/click-outside
close, launch-at-login, TTS, copy source, recapture, text-translate (⇧⌘T),
history submenu. Trạng thái từng phần:

### ĐÃ land (build OK, chưa có caller)

- `Providers/AIProviders.swift` — `translateText(settings:text:)` dispatch +
  `geminiTextTranslate` (system_instruction), `openAITextTranslate`
  (system+user messages), `claudeTextTranslate` (system param + user content)
- `Providers/Prompts.swift` — `textTranslatePrompt(targetLang:)`
- `Settings/Settings.swift` — `hotkeyKeyCode2`/`hotkeyModifiers2` (default
  ⇧⌘T = keyCode 17, mods 768), `launchAtLogin`
- `Overlay/Speech.swift` — `BTSpeech` @MainActor: `toggle/speak/stop` +
  voiceLang map (vi→vi-VN…) qua AVSpeechSynthesizer
- `Overlay/DismissWatcher.swift` — `init(frames:[CGRect], onDismiss:@MainActor
  @Sendable ()->Void)`: Esc bất kỳ + click ngoài frames → dismiss;
  `stop()`/deinit gỡ monitors. (Global + local monitors — global không thấy
  event trong app mình.)

### CHƯA land — còn phải viết (design đã chốt, theo thứ tự)

1. **FillOverlay.swift** (file `Overlay/FillOverlay.swift`):
   - `show()` signature thêm `onRefresh: (@MainActor () -> Void)? = nil`
   - **Explain card**: mode == .explain → thay segment boxes bằng 1 card
     scrollable (NSScrollView + NSTextView, font sans 13, bg paper ~0.98,
     radius 6, border hairline). Window mở rộng: extras stack [region][bar]
     [card] — `explainH = min(max(160, measuredText+28), screenH*0.4)`, kẹp
     vào khoảng trống phía extras; khi barBelow=false thì extras lật lên trên
     (regionY = barBelow ? extraH : 0, extraH = barH + explainH). Card y =
     barBelow ? 0 : rect.height + barH; bar y = barBelow ? explainH : rect.height
   - **Toolbar** thêm icon: `speaker.wave.2` → `BTSpeech.toggle(result.
     translation, lang: Settings.load().targetLang)`; `doc.plaintext` copy
     `result.source` (chỉ khi source non-empty); `arrow.clockwise` → onRefresh
   - **DismissWatcher** sau `window = win`:
     `dismissWatcher = DismissWatcher(frames: [win.frame]) { [weak self] in self?.close() }`
     — `close()` gọi `dismissWatcher?.stop(); dismissWatcher = nil`
   - **Segment click copy**: NSTextField subclass có `mouseDown` → copy
     `s.translation` + flash border accent 0.4s; toolTip "Click để copy đoạn này"
2. **`Overlay/TextResultPanel.swift` (mới)**: borderless floating panel ~360w,
   scrollable NSTextView hiển thị translation + toolbar nhỏ (copy/tts/close);
   đặt gần `NSEvent.mouseLocation`, clamp screen; DismissWatcher riêng
3. **`App/LoginItem.swift` (mới)**: LaunchAgent plist
   `~/Library/LaunchAgents/com.bntrans.mac.plist` (`ProgramArguments`=[abs
   binary path từ `CommandLine.arguments[0]` resolve tuyệt đối], `RunAtLoad:
   true`) — SMAppService KHÔNG dùng được vì binary swift run không bundle;
   `apply(_ enabled:)` gọi từ `settingsChanged()`
4. **AppDelegate.swift**:
   - Hotkey thứ 2: `EventHotKeyID(signature: 0x4254, id: 2)`; handler chung
     đọc `GetEventParameter(theEvent, kEventParamDirectObject,
     typeEventHotKeyID, &hkID)` → id 2 gọi `textTranslateClicked()`
   - `textTranslateClicked()`: AX selected text
     (`AXIsProcessTrustedWithOptions(prompt:true)` → systemWide element
     `kAXFocusedUIElement` → `kAXSelectedTextAttribute`) → fallback
     `NSPasteboard.general.string(forType:.string)` → `translateText` →
     `TextResultPanel.show`
   - **History submenu** trong status menu: in-memory tối đa ~8 entries
     `{result, rect, mode, image(CGImage đã scale ≤1280)}`; item click →
     `overlay.show(...)`; title = ~40 chars đầu của translation
5. **SettingsView.swift**: General→App thêm Toggle "Launch at login"
   (`$settings.launchAtLogin`, style `.instrumentSwitch`); General→Shortcut
   thêm row "Translate text" + `HotkeyRecorder(keyCode:
   $settings.hotkeyKeyCode2, modifiers: $settings.hotkeyModifiers2)`;
   AppDelegate thêm `updateTextMenuTitle()` giống `updateCaptureMenuTitle()`
6. **Verify**: `swift build` 0 warnings → chạy app → test E2E

### Đã quyết định BỎ qua (khỏi cân nhắc lại)

- Inline-replace (dịch rồi thay text trong app khác qua AX) — janky, ROI thấp
- Thêm provider nữa; custom theme; i18n UI; continuous subtitle translate

## Kiến trúc hiện tại

```
⇧⌘S → RegionSelector (dim + viền xanh + badge W×H NSTextField)
→ ScreenCaptureKit crop → JPEG ≤1280 → provider vision OCR+translate
→ FillOverlay: veil mỏng toàn vùng + segment plates (sample màu, 0.85 alpha,
  grow tỉ lệ thiên phải, grow xuống khi wrap dư, fitFont floor 9pt)
+ icon toolbar pill compact ⇧⌘T → (đang thêm) AX selection → clipboard
→ translateText (chat endpoints) → TextResultPanel
```

- Providers: gemini | openai-compat (openai/openrouter/groq/ollama/custom) |
  claude (Anthropic Messages, x-api-key + anthropic-version, image base64)
- `Providers/Models.swift` — fetch models per-provider; `--dump-models` flag
- `UI/Theme.swift` — BTTheme + BTFont (Plex bundled, PS names `-Medm`/`-SmBld`)
- Settings: UserDefaults `bntrans.settings`, auto-save + `.bntransSettingsChanged`

## Debug hooks

```sh
./.build/debug/BNTransMac --dump-models        # list model theo settings
./.build/debug/BNTransMac --open-settings      # mở Settings khi launch
```

Log `[BTFill]` mỗi lần overlay show → `/tmp/bntrans.log`.

## Đã fix xong (tham chiếu nếu tái phát)

- Crash `sizeWithAttributes` badge → NSTextField
- Khối đen → guard khi segments+translation đều rỗng
- Fill trắng → `interpolationQuality .high` (low = nearest-sample trúng glyph)
- Chữ gốc lòi phải → inflate box thiên phải; Plex font → đúng PS name

## Nhạy cảm

API keys trong UserDefaults local — không commit, không in ra.

## Style rules

- Tiếng Việt, gọi "bro"; conventional commits, tách theo task; không AI attribution
- Không bịa proof — verify bằng build + screenshot thật (`screencapture`)
