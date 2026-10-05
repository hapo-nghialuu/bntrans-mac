import AppKit
import Carbon
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private let overlay = FillOverlay()
    private var lastCropped: CGImage?
    private var lastRect: CGRect = .zero
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusItem.button?.title = "BT"

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Capture Area  ⇧⌘S",
            action: #selector(captureClicked),
            keyEquivalent: ""
        )
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

        registerHotKey()
    }

    // Global ⇧⌘S via Carbon RegisterEventHotKey — works without
    // accessibility permissions.
    private func registerHotKey() {
        let spec = EventHotKeyID(signature: OSType(0x4254), id: 1)
        var ref: EventHotKeyRef?
        // 's' = kVK_ANSI_S (1), cmd|shift modifiers
        RegisterEventHotKey(
            1,
            UInt32(cmdKey | shiftKey),
            spec,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKeyRef = ref
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

    @objc private func openSettings() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "BNTrans Settings"
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
