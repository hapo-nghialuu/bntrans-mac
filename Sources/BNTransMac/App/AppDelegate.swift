import AppKit
import Carbon
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerInstalled = false
    private let overlay = FillOverlay()
    private var lastCropped: CGImage?
    private var lastRect: CGRect = .zero
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .bntransSettingsChanged,
            object: nil
        )
    }

    @objc private func settingsChanged() {
        AppAppearance.apply(Settings.load().appearance)
        registerHotKey()
        updateCaptureMenuTitle()
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
        RegionSelector.select { [weak self] rect in
            guard let self, let rect else { return }
            self.lastRect = rect
            self.lastCropped = nil
            Task { await self.run(rect: rect, mode: .translate) }
        }
    }

    private func run(rect: CGRect, mode: ImageMode) async {
        let settings = Settings.load()
        do {
            if lastCropped == nil {
                lastCropped = try await captureRegion(rect)
            }
            guard let cropped = lastCropped else { return }
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
            _ = await MainActor.run {
                if settings.fillEnabled {
                    overlay.show(rect: rect, result: result, mode: mode) {
                        [weak self] m in
                        Task { await self?.run(rect: rect, mode: m) }
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
            }
        } catch {
            _ = await MainActor.run {
                NSAlert.error(with: error.localizedDescription).runModal()
            }
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
    func openSettingsForDebug() { openSettings() }

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
