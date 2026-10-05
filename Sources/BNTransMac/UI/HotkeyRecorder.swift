import AppKit
import Carbon
import SwiftUI

/// Settings control that displays the current capture hotkey and records a
/// new one when clicked — click, press the combo, Esc cancels. Values are
/// stored as `keyCode` + Carbon modifier flags (what `RegisterEventHotKey`
/// expects).
struct HotkeyRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    @State private var recording = false

    var body: some View {
        Button {
            recording = true
        } label: {
            Text(recording ? "Press shortcut…" : label)
                .font(.plexMono(11, weight: .medium))
                .foregroundStyle(recording ? BTTheme.accent : BTTheme.secondary)
                .padding(.horizontal, 8)
                .frame(minWidth: 96, minHeight: 28)
                .background(BTTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                        .strokeBorder(recording ? BTTheme.accent : BTTheme.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .background {
            HotkeyCapture(isActive: $recording) { kc, mods in
                keyCode = Int(kc)
                modifiers = Int(mods)
                recording = false
            } onCancel: {
                recording = false
            }
            .frame(width: 0, height: 0)
        }
        .help("Click, then press the new shortcut. Esc cancels.")
    }

    /// `⌃⌥⇧⌘K` style label from the stored Carbon flags + keyCode.
    private var label: String {
        var s = ""
        let m = UInt32(modifiers)
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName(for: UInt16(keyCode))
    }
}

/// Installs a local key-down monitor while `isActive`; reports the first
/// combo that has at least one modifier. Esc cancels.
private struct HotkeyCapture: NSViewRepresentable {
    @Binding var isActive: Bool
    var onCapture: (UInt16, UInt32) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if isActive {
            context.coordinator.install()
        } else {
            context.coordinator.remove()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor final class Coordinator {
        var parent: HotkeyCapture
        private var monitor: Any?

        init(_ parent: HotkeyCapture) { self.parent = parent }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                // Local key-down monitors always fire on the main thread —
                // hopping satisfies the compiler without changing behavior.
                Task { @MainActor in
                    guard let self else { return }
                    if event.keyCode == 53 { // Esc — cancel, keep old shortcut
                        self.parent.onCancel()
                        return
                    }
                    let mods = Self.carbonModifiers(event.modifierFlags)
                    guard mods != 0 else { return } // need a modifier
                    self.parent.onCapture(event.keyCode, mods)
                }
                return nil // swallow — don't type into other fields
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
            var m: UInt32 = 0
            if flags.contains(.command) { m |= UInt32(cmdKey) }
            if flags.contains(.shift) { m |= UInt32(shiftKey) }
            if flags.contains(.option) { m |= UInt32(optionKey) }
            if flags.contains(.control) { m |= UInt32(controlKey) }
            return m
        }
    }
}

/// Human-readable name for a virtual keyCode — letters/digits via the
/// current keyboard layout, common special keys hardcoded.
func keyName(for keyCode: UInt16) -> String {
    switch keyCode {
    case 36: return "↩"
    case 48: return "⇥"
    case 49: return "Space"
    case 51: return "⌫"
    case 53: return "⎋"
    case 76: return "⌤"
    case 115: return "↖"
    case 119: return "↘"
    case 116: return "⇞"
    case 121: return "⇟"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    case 122: return "F1"
    case 120: return "F2"
    case 99: return "F3"
    case 118: return "F4"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default: break
    }

    guard
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
            .takeRetainedValue(),
        let dataRef = TISGetInputSourceProperty(
            source, kTISPropertyUnicodeKeyLayoutData)
    else { return "?" }
    let layoutData = unsafeBitCast(dataRef, to: CFData.self)
    let layout = unsafeBitCast(
        CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
    var dead: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = UCKeyTranslate(
        layout,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &dead,
        4,
        &length,
        &chars
    )
    guard status == noErr, length > 0 else { return "?" }
    return String(utf16CodeUnits: chars, count: length).uppercased()
}
