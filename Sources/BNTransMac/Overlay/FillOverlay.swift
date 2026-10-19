import AppKit

/// Borderless window painted over the captured region, with a floating
/// toolbar and either translated segment plates or a scrollable explanation.
@MainActor final class FillOverlay: NSObject {
    private var window: NSWindow?
    private var dismissWatcher: DismissWatcher?
    private var onMode: (@MainActor (ImageMode) -> Void)?

    func show(
        rect: CGRect,
        result: ImageResult,
        mode: ImageMode,
        image: CGImage?,
        onRefresh: (@MainActor () -> Void)? = nil,
        onMode: @escaping @MainActor (ImageMode) -> Void
    ) {
        close()
        self.onMode = onMode

        // An empty box over the whole region is the "black slab" bug.
        guard !result.segments.isEmpty || !result.translation.isEmpty
        else { return }

        let barH: CGFloat = 28
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
                Self.copy(result.translation)
            })
        if !result.source.isEmpty {
            stack.addArrangedSubview(
                iconButton(symbol: "doc.plaintext", tip: "Copy bản gốc", active: false) {
                    Self.copy(result.source)
                })
        }
        stack.addArrangedSubview(
            iconButton(symbol: "speaker.wave.2", tip: "Đọc bản dịch", active: false) {
                BTSpeech.toggle(result.translation, lang: Settings.load().targetLang)
            })
        if let onRefresh {
            stack.addArrangedSubview(
                iconButton(symbol: "arrow.clockwise", tip: "Chụp lại", active: false) {
                    onRefresh()
                })
        }
        stack.addArrangedSubview(
            iconButton(symbol: "xmark", tip: "Đóng", active: false) {
                [weak self] in self?.close()
            })
        let barW = stack.arrangedSubviews.reduce(0) {
            $0 + $1.frame.width
        } + stack.spacing * CGFloat(stack.arrangedSubviews.count - 1)
            + stack.edgeInsets.left + stack.edgeInsets.right
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })
        let bounds = screen?.visibleFrame ?? rect.insetBy(dx: -300, dy: -300)
        let width = min(max(max(rect.width, barW), mode == .explain ? 260 : 0), bounds.width)
        let extrasX = min(max(rect.minX, bounds.minX), bounds.maxX - width)

        let text = result.translation as NSString
        let textWidth = max(1, width - 44)
        let measuredText = text.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: BTFont.sans(13)]
        ).height
        let desiredCardH = mode == .explain
            ? min(max(160, ceil(measuredText) + 28), bounds.height * 0.4) : 0
        let belowSpace = max(0, rect.minY - bounds.minY)
        let aboveSpace = max(0, bounds.maxY - rect.maxY)
        let barBelow = belowSpace >= barH + desiredCardH
            || (aboveSpace < barH + desiredCardH && belowSpace >= aboveSpace)
        let space = barBelow ? belowSpace : aboveSpace
        let availableCardH = mode == .explain
            ? min(desiredCardH, max(0, space - barH)) : 0
        let usableRegion = rect.intersection(bounds)
        let cardInside = mode == .explain && availableCardH < 100 && usableRegion.height >= 160
        let cardH = cardInside
            ? min(desiredCardH, usableRegion.height - barH) : availableCardH
        let barInside = cardInside
            || (mode == .translate && max(belowSpace, aboveSpace) < barH
                && usableRegion.height >= barH)
        let extrasH = barH + cardH
        let preferredY = barInside ? usableRegion.minY
            : (barBelow ? rect.minY - extrasH : rect.maxY)
        let extrasY = min(max(preferredY, bounds.minY), bounds.maxY - extrasH)
        let extrasFrame = CGRect(x: extrasX, y: extrasY, width: width, height: extrasH)
        let windowFrame = rect.union(extrasFrame)
        let regionX = rect.minX - windowFrame.minX
        let regionY = rect.minY - windowFrame.minY
        let extrasOffset = CGPoint(
            x: extrasX - windowFrame.minX, y: extrasY - windowFrame.minY)
        let win = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.hasShadow = false

        let root = NSView(frame: NSRect(origin: .zero, size: win.frame.size))
        root.wantsLayer = true
        if mode == .translate {
            let veil = NSView(frame: CGRect(
                x: regionX, y: regionY, width: rect.width, height: rect.height))
            veil.wantsLayer = true
            veil.layer?.backgroundColor = (
                image.flatMap {
                    averageColor(of: $0, box: Segment(
                        box: [0, 0, 1000, 1000], source: "", translation: ""))
                } ?? NSColor(BTTheme.background)
            ).withAlphaComponent(0.85).cgColor
            root.addSubview(veil)
            let segs = result.segments.isEmpty
                ? [Segment(box: [0, 0, 1000, 1000], source: "", translation: result.translation)]
                : result.segments
            for s in segs {
                root.addSubview(segmentView(
                    s, in: rect.size, offset: CGPoint(x: regionX, y: regionY), image: image))
            }
        } else if cardH > 0 {
            root.addSubview(explainCard(
                text: result.translation,
                frame: CGRect(x: extrasOffset.x,
                              y: extrasOffset.y + (barBelow || cardInside ? 0 : barH),
                              width: width, height: cardH)))
        }

        let bar = NSView(frame: CGRect(
            x: extrasOffset.x,
            y: extrasOffset.y + (barBelow || barInside ? cardH : 0),
            width: barW, height: barH))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(BTTheme.background)
            .withAlphaComponent(0.96).cgColor
        bar.layer?.cornerRadius = 6
        bar.layer?.borderWidth = 1
        bar.layer?.borderColor = NSColor(BTTheme.border).cgColor
        stack.frame = bar.bounds
        bar.addSubview(stack)
        root.addSubview(bar)

        win.contentView = root
        win.orderFront(nil)
        window = win
        dismissWatcher = DismissWatcher(frames: [win.frame]) { [weak self, weak win] in
            guard self?.window === win else { return }
            self?.close()
        }
    }

    func close() {
        dismissWatcher?.stop()
        dismissWatcher = nil
        BTSpeech.stop()
        window?.orderOut(nil)
        window = nil
        onMode = nil
    }

    private func explainCard(text: String, frame: CGRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(BTTheme.background).cgColor
        card.layer?.borderColor = NSColor(BTTheme.border).cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 6

        let scroll = NSScrollView(frame: card.bounds.insetBy(dx: 10, dy: 8))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0, width: scroll.contentSize.width, height: scroll.contentSize.height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = BTFont.sans(13)
        textView.textColor = NSColor(BTTheme.primary)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text
        scroll.documentView = textView
        card.addSubview(scroll)
        return card
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Map normalized 0-1000 box → a view positioned over the region. The
    /// box is inflated a few points so translated text fully covers the
    /// original glyphs, filled with the colour sampled underneath (like a
    /// quick inpaint), and bordered by nothing — the border is what made
    /// segments read as pasted labels.
    private func segmentView(
        _ s: Segment, in size: CGSize, offset: CGPoint, image: CGImage?
    ) -> NSView {
        let yMin = s.box[0] / 1000, xMin = s.box[1] / 1000
        let yMax = s.box[2] / 1000, xMax = s.box[3] / 1000
        // box y is top-down (image space); flip for Cocoa
        var f = CGRect(
            x: offset.x + xMin * size.width,
            y: offset.y + (1 - yMax) * size.height,
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
            CGRect(origin: offset, size: size))

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
            let bottom = max(offset.y, f.maxY - (need.height + 2))
            f = CGRect(
                x: f.minX, y: bottom,
                width: f.width, height: f.maxY - bottom)
        }

        let v = CopySegmentLabel(text: s.translation)
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
        v.toolTip = "Bấm để copy bản dịch"
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

private final class CopySegmentLabel: NSTextField {
    init(text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        cell?.wraps = true
        cell?.isScrollable = false
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(stringValue, forType: .string)
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(BTTheme.accent).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.layer?.borderWidth = 0
        }
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
