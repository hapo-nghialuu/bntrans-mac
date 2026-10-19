import AppKit
import Carbon
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerInstalled = false
    private let overlay = FillOverlay()
    private var lastCropped: CGImage?
    private var captureGeneration = 0
    private var settingsWindow: NSWindow?
    private var captureMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BTFont.registerBundledFonts()
        AppAppearance.apply(Settings.load().appearance)
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let url = Bundle.module.url(
            forResource: "icon-38",
            withExtension: "png",
            subdirectory: "Resources/Icons"
        ) ?? Bundle.module.url(forResource: "icon-38", withExtension: "png"),
            let img = NSImage(contentsOf: url)
        {
            img.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "BT"
        }

        let menu = NSMenu()
        captureMenuItem = NSMenuItem(
            title: "Capture Area",
            action: #selector(captureClicked),
            keyEquivalent: ""
        )
        menu.addItem(captureMenuItem!)
        updateCaptureMenuTitle()
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu

        // Without a main menu, ⌘V/⌘A/⌘X/⌘C never reach the text fields —
        // AppKit routes editing commands through the menu bar, and an
        // LSUIElement app has none by default. A minimal Edit menu fixes
        // paste/select-all in every field.
        installMainMenu()

        registerHotKey()
        let s = Settings.load()
        lastHotkey = (s.hotkeyKeyCode, s.hotkeyModifiers)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .bntransSettingsChanged,
            object: nil
        )
    }

    /// Auto-save fires on every settings field edit — only re-register the
    /// Carbon hotkey when the actual combo changed, not on each keystroke.
    private var lastHotkey: (key: Int, mods: Int)?

    @objc private func settingsChanged() {
        let s = Settings.load()
        AppAppearance.apply(s.appearance)
        let combo = (s.hotkeyKeyCode, s.hotkeyModifiers)
        if lastHotkey?.key != combo.0 || lastHotkey?.mods != combo.1 {
            lastHotkey = combo
            registerHotKey()
            updateCaptureMenuTitle()
        }
    }

    /// Minimal main menu — just an Edit submenu with the standard items so
    /// text-editing shortcuts work inside the Settings window.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(
            withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(
            withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(
            withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(
            withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a")
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func updateCaptureMenuTitle() {
        let s = Settings.load()
        var mods = ""
        let m = UInt32(s.hotkeyModifiers)
        if m & UInt32(controlKey) != 0 { mods += "⌃" }
        if m & UInt32(optionKey) != 0 { mods += "⌥" }
        if m & UInt32(shiftKey) != 0 { mods += "⇧" }
        if m & UInt32(cmdKey) != 0 { mods += "⌘" }
        captureMenuItem?.title =
            "Capture Area  \(mods)\(keyName(for: UInt16(s.hotkeyKeyCode)))"
    }

    // Global hotkey via Carbon RegisterEventHotKey — works without
    // accessibility permissions. KeyCode + modifiers come from Settings so
    // the user can rebind it in General → Shortcut.
    private func registerHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let settings = Settings.load()
        let spec = EventHotKeyID(signature: OSType(0x4254), id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(settings.hotkeyKeyCode),
            UInt32(settings.hotkeyModifiers),
            spec,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKeyRef = ref

        // Install the pressed-event handler once — re-registering the hotkey
        // must not stack handlers or every press would fire N times.
        guard !hotKeyHandlerInstalled else { return }
        hotKeyHandlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                Task { @MainActor in
                    (NSApp.delegate as? AppDelegate)?.captureClicked()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    @objc private func captureClicked() {
        captureGeneration += 1
        let generation = captureGeneration
        overlay.close()
        RegionSelector.select { [weak self] rect in
            guard let self, let rect, self.captureGeneration == generation else { return }
            self.lastCropped = nil
            Task { await self.run(rect: rect, mode: .translate, generation: generation) }
        }
    }

    private func rerun(rect: CGRect, mode: ImageMode, recapture: Bool) {
        captureGeneration += 1
        overlay.close()
        if recapture {
            lastCropped = nil
        }
        let generation = captureGeneration
        Task { await run(rect: rect, mode: mode, generation: generation) }
    }

    private func run(rect: CGRect, mode: ImageMode, generation: Int) async {
        let settings = Settings.load()
        do {
            let cropped: CGImage
            if let cached = lastCropped {
                cropped = cached
            } else {
                cropped = try await captureRegion(rect)
                guard generation == captureGeneration else { return }
                lastCropped = cropped
            }
            let maxDim: CGFloat = 1280
            let rep = NSBitmapImageRep(cgImage: cropped)
            let scale = min(
                1,
                maxDim / CGFloat(max(rep.pixelsWide, rep.pixelsHigh))
            )
            let jpeg: Data
            if scale < 1, let scaled = resize(rep, by: scale) {
                jpeg = scaled
            } else {
                jpeg =
                    rep.representation(
                        using: .jpeg,
                        properties: [.compressionFactor: 0.85]
                    ) ?? Data()
            }
            let result = try await translateImage(
                settings: settings,
                imageBase64: jpeg.base64EncodedString(),
                mimeType: "image/jpeg",
                targetLang: settings.targetLang,
                mode: mode
            )
            guard generation == captureGeneration else { return }
            if settings.fillEnabled {
                overlay.show(
                    rect: rect, result: result, mode: mode,
                    image: cropped,
                    onRefresh: { [weak self] in
                        self?.rerun(rect: rect, mode: mode, recapture: true)
                    }
                ) { [weak self] m in
                    self?.rerun(rect: rect, mode: m, recapture: false)
                }
            } else {
                // popup fallback — translation text in a plain alert
                let a = NSAlert()
                a.messageText = "Translation"
                a.informativeText = result.translation
                a.addButton(withTitle: "Copy")
                a.addButton(withTitle: "Close")
                if a.runModal() == .alertFirstButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        result.translation,
                        forType: .string
                    )
                }
            }
        } catch {
            guard generation == captureGeneration else { return }
            NSAlert.error(with: error.localizedDescription).runModal()
        }
    }

    private func resize(_ rep: NSBitmapImageRep, by scale: CGFloat) -> Data? {
        let w = Int(CGFloat(rep.pixelsWide) * scale)
        let h = Int(CGFloat(rep.pixelsHigh) * scale)
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        rep.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.85]
        )
    }

    /// Non-objc entry point so the `--open-settings` debug flag can reuse it.
    func openSettingsForDebug() {
        openSettings()
        if CommandLine.arguments.contains("--click-select") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.postClickOnSelectAnchor()
            }
        }
    }

    /// Debug: synthesize a real mouse click at the model select's anchor so
    /// the full event-dispatch path (hit-test → Button → isOpen → panel) is
    /// exercised exactly like a user click. Logs the outcome.
    private func postClickOnSelectAnchor() {
        guard let win = settingsWindow,
              let anchor = Self.findView(
                identified: "bt-select-anchor", in: win.contentView) else {
            NSLog("[BTClick] no window/anchor")
            return
        }
        let centerInWindow = anchor.convert(
            CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        NSLog("[BTClick] anchor frame %@ -> window %@", String(describing: anchor.frame), String(describing: centerInWindow))
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            guard let ev = NSEvent.mouseEvent(
                with: type, location: centerInWindow,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: win.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
                continue
            }
            NSApp.postEvent(ev, atStart: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let panels = (win.childWindows ?? []).map {
                "panel frame=\($0.frame) visible=\($0.isVisible)"
            }
            NSLog("[BTClick] after click, children: %@", panels.joined(separator: " | "))
        }
    }

    private static func findView(
        identified id: String, in view: NSView?
    ) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == id { return view }
        for sub in view.subviews {
            if let found = findView(identified: id, in: sub) { return found }
        }
        return nil
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "BNTrans"
            win.minSize = NSSize(width: 720, height: 560)
            win.contentView = NSHostingView(rootView: SettingsView())
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension NSAlert {
    static func error(with message: String) -> NSAlert {
        let a = NSAlert()
        a.messageText = "BNTrans"
        a.informativeText = message
        a.alertStyle = .warning
        return a
    }
}
