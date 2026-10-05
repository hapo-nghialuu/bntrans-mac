import AppKit

/// Borderless window painted over the captured region — same idea as the
/// extension's .bt-shot-fill: a pill toolbar (Translate / Explain / ×)
/// plus opaque per-segment boxes covering the original text.
@MainActor final class FillOverlay: NSObject {
    private var window: NSWindow?
    private var regionRect: CGRect = .zero
    private var onMode: (@MainActor (ImageMode) -> Void)?

    func show(
        rect: CGRect,
        result: ImageResult,
        mode: ImageMode,
        onMode: @escaping @MainActor (ImageMode) -> Void
    ) {
        close()
        self.regionRect = rect
        self.onMode = onMode

        let barH: CGFloat = 30
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.hasShadow = false

        let root = NSView(frame: NSRect(origin: .zero, size: rect.size))
        root.wantsLayer = true

        // toolbar pill, pinned above the region (flips inside if near top)
        let bar = NSView(
            frame: NSRect(
                x: 0,
                y: rect.height,
                width: rect.width,
                height: barH
            )
        )
        // flip inside when the bar would overflow the screen top
        if let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(rect)
        }), rect.maxY + barH > screen.frame.maxY {
            bar.frame.origin.y = rect.height - barH
        }
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.95).cgColor
        bar.layer?.cornerRadius = 8
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        let tr = pillButton(
            title: "Dịch",
            active: mode == .translate
        ) { [weak self] in self?.onMode?(.translate) }
        let ex = pillButton(
            title: "Giải thích",
            active: mode == .explain
        ) { [weak self] in self?.onMode?(.explain) }
        let x = pillButton(title: "×", active: false) { [weak self] in
            self?.close()
        }
        stack.addArrangedSubview(tr)
        stack.addArrangedSubview(ex)
        stack.addArrangedSubview(x)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        root.addSubview(bar)

        // window = region + barH on top; the bar sits inside that extra band
        // (or flipped inside the top edge when the region hugs the screen top)
        win.setFrame(
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height + barH
            ),
            display: false
        )
        root.frame = NSRect(
            origin: .zero,
            size: CGSize(width: rect.width, height: rect.height + barH)
        )
        bar.frame.origin.y =
            bar.frame.origin.y == rect.height ? rect.height : rect.height - barH

        // segments — opaque boxes covering the original text
        let segs = result.segments.isEmpty
            ? [Segment(box: [0, 0, 1000, 1000], source: "", translation: result.translation)]
            : result.segments
        for s in segs {
            root.addSubview(
                segmentView(s, in: rect.size, barH: barH)
            )
        }

        win.contentView = root
        win.orderFront(nil)
        window = win
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    /// Map normalized 0-1000 box → a view positioned over the region.
    private func segmentView(_ s: Segment, in size: CGSize, barH: CGFloat)
        -> NSView
    {
        let yMin = s.box[0] / 1000, xMin = s.box[1] / 1000
        let yMax = s.box[2] / 1000, xMax = s.box[3] / 1000
        // box y is top-down (image space); flip for Cocoa
        let f = CGRect(
            x: xMin * size.width,
            y: (1 - yMax) * size.height,
            width: max(1, (xMax - xMin) * size.width),
            height: max(1, (yMax - yMin) * size.height)
        )
        let v = NSTextField(
            wrappingLabelWithString: s.translation
        )
        v.frame = f
        v.isBezeled = false
        v.drawsBackground = true
        v.backgroundColor = NSColor.windowBackgroundColor
        v.textColor = .labelColor
        v.alignment = .center
        v.font = fitFont(text: s.translation, in: f.size)
        v.wantsLayer = true
        v.layer?.cornerRadius = 3
        return v
    }

    /// Shrink the font until the text fits its box (same trick as the
    /// extension's fill segments).
    private func fitFont(text: String, in size: CGSize) -> NSFont {
        var pt = min(18, size.height - 2)
        while pt > 7 {
            let f = NSFont.systemFont(ofSize: pt)
            let need = (text as NSString).boundingRect(
                with: CGSize(width: size.width - 4, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: f]
            ).size
            if need.height <= size.height { return f }
            pt -= 1
        }
        return NSFont.systemFont(ofSize: 7)
    }

    private func pillButton(
        title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let b = CallbackButton(title: title, target: nil, action: nil)
        b.onClick = action
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 6
        b.contentTintColor = active ? .white : .labelColor
        b.layer?.backgroundColor =
            active
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
        b.font = .systemFont(ofSize: 12, weight: .medium)
        return b
    }
}

private final class CallbackButton: NSButton {
    var onClick: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError() }
    convenience init(title: String, target: Any?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
    }
    @objc private func clicked() { onClick?() }
}
