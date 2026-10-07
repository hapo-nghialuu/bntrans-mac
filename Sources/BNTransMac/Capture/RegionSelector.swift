import AppKit

/// Covers every screen with a dim translucent panel; the user drags a
/// rectangle and gets it back in global Cocoa coordinates (y-up).
/// Esc or right-click cancels → completion(nil).
typealias RegionCompletion = @MainActor (CGRect?) -> Void

@MainActor final class RegionSelector {
    private var panels: [NSPanel] = []
    private var done = false
    private static var active = false
    private static var current: RegionSelector?

    static func select(completion: @escaping RegionCompletion) {
        guard !active else { return } // ignore double-trigger
        active = true
        let sel = RegionSelector()
        current = sel // keep alive until finish
        sel.run { r in
            active = false
            current = nil
            completion(r)
        }
    }

    private func run(completion: @escaping RegionCompletion) {
        for screen in NSScreen.screens {
            let view = SelectionView(screenFrame: screen.frame) { [weak self] rect in
                self?.finish(rect: rect, completion: completion)
            }
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
    }

    private func finish(rect: CGRect?, completion: RegionCompletion) {
        guard !done else { return }
        done = true
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        completion(rect)
    }
}

/// Per-screen drag view: dims everything, cuts a clear hole + border for
/// the dragged rect (same look as the extension's selection overlay).
private final class SelectionView: NSView {
    private let onFinish: RegionCompletion
    private var start: NSPoint?
    private var current: NSRect = .zero

    init(screenFrame: NSRect, onFinish: @escaping RegionCompletion) {
        self.onFinish = onFinish
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))

        // Hint pill at top-center — Plex Sans on a dark plate.
        let hint = NSTextField(labelWithString: "Drag to select  ·  Esc to cancel")
        hint.font = BTFont.sans(12, weight: .medium)
        hint.textColor = .white
        hint.isBezeled = false
        hint.drawsBackground = true
        hint.backgroundColor = NSColor(BTTheme.primary).withAlphaComponent(0.85)
        hint.wantsLayer = true
        hint.layer?.cornerRadius = 4
        hint.alignment = .center
        hint.sizeToFit()
        let pad: CGFloat = 10
        hint.frame.size.width += pad * 2
        hint.frame.size.height += 6
        hint.frame.origin = NSPoint(
            x: (screenFrame.width - hint.frame.width) / 2,
            y: screenFrame.height - hint.frame.height - 40
        )
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // Esc
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = start else { return }
        let p = convert(event.locationInWindow, from: nil)
        current = NSRect(
            x: min(s.x, p.x),
            y: min(s.y, p.y),
            width: abs(p.x - s.x),
            height: abs(p.y - s.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard current.width > 4, current.height > 4 else {
            start = nil
            current = .zero
            needsDisplay = true
            return
        }
        // local view coords == screen coords (view fills the screen, same origin)
        let screenRect = window!.convertToScreen(current)
        onFinish(screenRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        dirtyRect.fill()
        guard current != .zero else { return }

        NSColor.clear.setFill()
        current.fill(using: .copy) // punch a hole

        // green selection border + W × H badge — the look of classic
        // screen-translate tools (Screen Translate / Pot style)
        NSColor(srgbRed: 0.20, green: 0.82, blue: 0.36, alpha: 1).setStroke()
        let path = NSBezierPath(rect: current.insetBy(dx: 0.75, dy: 0.75))
        path.lineWidth = 1.5
        path.stroke()

        let label = "\(Int(current.width)) × \(Int(current.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: BTFont.mono(10, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 5
        var badge = NSRect(
            x: current.minX,
            y: current.maxY + 5,
            width: textSize.width + pad * 2,
            height: textSize.height + pad
        )
        if badge.maxY > bounds.maxY - 4 {
            badge.origin.y = current.maxY - badge.height - 5 // flip inside
        }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
        (label as NSString).draw(
            at: NSPoint(
                x: badge.minX + pad,
                y: badge.minY + (badge.height - textSize.height) / 2),
            withAttributes: attrs)
    }
}
