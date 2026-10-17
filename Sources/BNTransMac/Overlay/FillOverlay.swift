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
        image: CGImage?,
        onMode: @escaping @MainActor (ImageMode) -> Void
    ) {
        close()
        self.regionRect = rect
        self.onMode = onMode

        NSLog(
            "[BTFill] mode=%@ segments=%d translationLen=%d first=%@",
            "\(mode)", result.segments.count, result.translation.count,
            String(result.translation.prefix(80)))
        // nothing recognised and nothing translated — an empty box over
        // the whole region is the "black slab" bug, so bail out entirely
        guard !result.segments.isEmpty || !result.translation.isEmpty
        else { return }

        let barH: CGFloat = 28
        // icon toolbar pinned under the region's bottom edge (the classic
        // screen-translate look); flips above the top edge when the region
        // hugs the bottom of the screen
        var barBelow = true
        if let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(rect)
        }), rect.minY - barH < screen.frame.minY {
            barBelow = false
        }
        let segYOffset: CGFloat = barBelow ? barH : 0

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

        let root = NSView(
            frame: NSRect(
                origin: .zero,
                size: CGSize(width: rect.width, height: rect.height + barH)
            )
        )
        root.wantsLayer = true

        let bar = NSView(
            frame: NSRect(
                x: 0,
                y: barBelow ? 0 : rect.height,
                width: rect.width,
                height: barH
            )
        )
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(BTTheme.background)
            .withAlphaComponent(0.96).cgColor
        bar.layer?.cornerRadius = 6
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor(BTTheme.border).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        stack.addArrangedSubview(
            iconButton(
                symbol: "globe", tip: "Dịch",
                active: mode == .translate
            ) { [weak self] in self?.onMode?(.translate) })
        stack.addArrangedSubview(
            iconButton(
                symbol: "lightbulb", tip: "Giải thích",
                active: mode == .explain
            ) { [weak self] in self?.onMode?(.explain) })
        stack.addArrangedSubview(
            iconButton(
                symbol: "doc.on.doc", tip: "Copy bản dịch", active: false
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.translation, forType: .string)
            })
        stack.addArrangedSubview(
            iconButton(symbol: "xmark", tip: "Đóng", active: false) {
                [weak self] in self?.close()
            })
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        // compact pill hugging the icon row — a full-width strip reads as
        // a heavy bar instead of a floating tool cluster
        bar.frame.size.width = stack.arrangedSubviews.reduce(0) {
            $0 + $1.frame.width
        } + stack.spacing * CGFloat(stack.arrangedSubviews.count - 1)
            + stack.edgeInsets.left + stack.edgeInsets.right
        root.addSubview(bar)

        // window = region + barH band; with the bar below, the band hangs
        // under the region so segments shift up by barH inside the window
        win.setFrame(
            CGRect(
                x: rect.minX,
                y: barBelow ? rect.minY - barH : rect.minY,
                width: rect.width,
                height: rect.height + barH
            ),
            display: false
        )

        // thin veil over the whole captured region — gaps between
        // segment plates show this tint instead of the raw page
        let veil = NSView(
            frame: CGRect(
                x: 0, y: segYOffset, width: rect.width, height: rect.height))
        veil.wantsLayer = true
        veil.layer?.backgroundColor = (
            image.flatMap {
                averageColor(
                    of: $0,
                    box: Segment(
                        box: [0, 0, 1000, 1000], source: "", translation: ""))
            } ?? NSColor(BTTheme.background)
        ).withAlphaComponent(0.85).cgColor
        root.addSubview(veil)

        // segments — opaque boxes covering the original text
        let segs = result.segments.isEmpty
            ? [Segment(box: [0, 0, 1000, 1000], source: "", translation: result.translation)]
            : result.segments
        for s in segs {
            root.addSubview(
                segmentView(s, in: rect.size, yOffset: segYOffset, image: image)
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

    /// Map normalized 0-1000 box → a view positioned over the region. The
    /// box is inflated a few points so translated text fully covers the
    /// original glyphs, filled with the colour sampled underneath (like a
    /// quick inpaint), and bordered by nothing — the border is what made
    /// segments read as pasted labels.
    private func segmentView(
        _ s: Segment, in size: CGSize, yOffset: CGFloat, image: CGImage?
    ) -> NSView {
        let yMin = s.box[0] / 1000, xMin = s.box[1] / 1000
        let yMax = s.box[2] / 1000, xMax = s.box[3] / 1000
        // box y is top-down (image space); flip for Cocoa
        var f = CGRect(
            x: xMin * size.width,
            y: yOffset + (1 - yMax) * size.height,
            width: max(1, (xMax - xMin) * size.width),
            height: max(1, (yMax - yMin) * size.height)
        )
        // Vision boxes run tighter than the true glyphs — worst on the
        // right edge (LTR bias), where trailing characters peek out.
        // Grow proportionally to the box, biased right, and clamp to the
        // region band so segments never dip into the toolbar strip.
        let growL = max(6, f.width * 0.08)
        let growR = max(10, f.width * 0.14)
        let growV = max(4, f.height * 0.10)
        f = CGRect(
            x: f.minX - growL,
            y: f.minY - growV,
            width: f.width + growL + growR,
            height: f.height + growV * 2
        ).intersection(
            CGRect(x: 0, y: yOffset, width: size.width, height: size.height))

        let fill = image.flatMap { averageColor(of: $0, box: s) }
            ?? NSColor(BTTheme.background)
        let lum = Self.luminance(of: fill)

        let font = fitFont(text: s.translation, in: f.size)
        // let the box grow downward when even the 9pt floor still wraps
        // past it — translations run longer than the detected glyphs
        let need = (s.translation as NSString).boundingRect(
            with: CGSize(
                width: f.width - 4, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        ).size
        if need.height + 2 > f.height {
            let bottom = max(yOffset, f.maxY - (need.height + 2))
            f = CGRect(
                x: f.minX, y: bottom,
                width: f.width, height: f.maxY - bottom)
        }

        let v = NSTextField(
            wrappingLabelWithString: s.translation
        )
        v.frame = f
        v.isBezeled = false
        v.drawsBackground = true
        // thin translucent wash — the capture ghosts through slightly
        // instead of an opaque slab
        v.backgroundColor = fill.withAlphaComponent(0.85)
        v.textColor = lum > 0.6
            ? NSColor(srgbRed: 0.086, green: 0.082, blue: 0.059, alpha: 1) // ink
            : NSColor(srgbRed: 0.949, green: 0.941, blue: 0.910, alpha: 1) // paper
        v.alignment = .center
        v.font = font
        v.wantsLayer = true
        v.layer?.cornerRadius = 3
        return v
    }

    /// Average colour of the pixels under a segment — renders the image
    /// crop into a single 1×1 context.
    private func averageColor(of image: CGImage, box s: Segment) -> NSColor? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let px = CGRect(
            x: s.box[1] / 1000 * w,
            y: s.box[0] / 1000 * h,
            width: max(1, (s.box[3] - s.box[1]) / 1000 * w),
            height: max(1, (s.box[2] - s.box[0]) / 1000 * h)
        ).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard px.width > 1, px.height > 1,
              let cropped = image.cropping(to: px) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // .high averages the crop — .low/.none nearest-sample a single
        // source pixel, so a lone white glyph paints the whole box white
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    private static func luminance(of color: NSColor) -> CGFloat {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0.5 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Shrink the font until the text fits its box (same trick as the
    /// extension's fill segments). Floor at 9pt — smaller is unreadable,
    /// so let it overflow the box slightly instead.
    private func fitFont(text: String, in size: CGSize) -> NSFont {
        var pt = min(18, size.height - 2)
        while pt > 9 {
            let f = BTFont.sans(pt, weight: .medium)
            let need = (text as NSString).boundingRect(
                with: CGSize(width: size.width - 4, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: f]
            ).size
            if need.height <= size.height { return f }
            pt -= 1
        }
        return BTFont.sans(9, weight: .medium)
    }

    /// Square icon button (SF Symbol on paper), like the tool rows in
    /// screen-translate apps — accent fill marks the active mode.
    private func iconButton(
        symbol: String,
        tip: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let b = CallbackButton(title: "", target: nil, action: nil)
        b.onClick = action
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 4
        b.image = NSImage(
            systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(
                .init(pointSize: 12, weight: .medium))
        b.contentTintColor = active
            ? .white : NSColor(BTTheme.primary)
        b.layer?.backgroundColor = active
            ? NSColor(BTTheme.accent).cgColor : NSColor.clear.cgColor
        b.toolTip = tip
        b.frame.size = NSSize(width: 24, height: 24)
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
