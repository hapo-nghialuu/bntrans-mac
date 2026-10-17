import AppKit

/// Dismiss gestures for floating panels: Esc anywhere, or a click outside
/// the watched area. Global monitors see events targeted at other apps;
/// local monitors cover clicks inside our own app (status menu, settings),
/// which global monitors never report.
final class DismissWatcher {
    private var monitors: [Any] = []

    /// `frames` are captured once — overlay panels don't move or resize
    /// while shown, so a static frame list is enough to hit-test clicks.
    /// `onDismiss` runs on the main actor (it touches NSWindow state).
    init(frames: [CGRect], onDismiss: @escaping @MainActor @Sendable () -> Void) {
        let isOutside = {
            let p = NSEvent.mouseLocation
            return !frames.contains { $0.contains(p) }
        }
        let dismiss = { _ = Task { @MainActor in onDismiss() } }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { e in
            if e.keyCode == 53 { dismiss() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { _ in if isOutside() { dismiss() } }
        ) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in
            if e.keyCode == 53 { dismiss() }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { e in if isOutside() { dismiss() }; return e }
        ) { monitors.append(m) }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
    }

    deinit { stop() }
}
