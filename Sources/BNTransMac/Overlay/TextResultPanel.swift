import AppKit

/// Floating result card for the selection/clipboard translation hotkey.
/// Unlike the screenshot fill, this is a separate readable panel anchored
/// near the pointer rather than a repaint of the original UI.
@MainActor final class TextResultPanel: NSObject {
    private var window: NSPanel?
    private var dismissWatcher: DismissWatcher?
    private var onDismiss: (@MainActor () -> Void)?
    private var source = ""
    private var translation = ""

    func showLoading(source: String, onDismiss: (@MainActor () -> Void)? = nil) {
        show(source: source, translation: "Đang dịch…", loading: true, onDismiss: onDismiss)
    }

    func show(
        source: String,
        translation: String,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        show(source: source, translation: translation, loading: false, onDismiss: onDismiss)
    }

    func close() {
        dismissWatcher?.stop()
        dismissWatcher = nil
        BTSpeech.stop()
        window?.orderOut(nil)
        window = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    private func show(
        source: String,
        translation: String,
        loading: Bool,
        onDismiss: (@MainActor () -> Void)?
    ) {
        close()
        self.source = source
        self.translation = translation
        self.onDismiss = onDismiss

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let bounds = screen?.visibleFrame ?? CGRect(
            x: mouse.x - 400, y: mouse.y - 400, width: 800, height: 800)
        let width: CGFloat = 380
        let textWidth = width - 60
        let measured = (translation as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: BTFont.sans(13)]
        ).height
        let maxHeight = min(420, bounds.height * 0.55)
        let height = min(max(150, ceil(measured) + 104), maxHeight)
        let x = min(
            max(mouse.x + 16, bounds.minX + 8),
            bounds.maxX - width - 8
        )
        let belowY = mouse.y - height - 16
        let y = belowY >= bounds.minY + 8
            ? belowY
            : min(max(mouse.y + 16, bounds.minY + 8), bounds.maxY - height - 8)

        let win = NSPanel(
            contentRect: CGRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.hasShadow = true
        win.hidesOnDeactivate = false
        win.becomesKeyOnlyIfNeeded = true
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = false

        let root = NSView(frame: NSRect(origin: .zero, size: win.frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(BTTheme.background)
            .withAlphaComponent(0.98).cgColor
        root.layer?.borderColor = NSColor(BTTheme.border).cgColor
        root.layer?.borderWidth = 1
        root.layer?.cornerRadius = 8

        let header = NSTextField(labelWithString: "BẢN DỊCH")
        header.font = BTFont.sans(10, weight: .semibold)
        header.textColor = NSColor(BTTheme.secondary)
        header.frame = CGRect(x: 16, y: height - 28, width: 160, height: 16)
        root.addSubview(header)

        let topRule = NSView(frame: CGRect(
            x: 0, y: height - 35, width: width, height: 1))
        topRule.wantsLayer = true
        topRule.layer?.backgroundColor = NSColor(BTTheme.hairline).cgColor
        root.addSubview(topRule)

        let footerH: CGFloat = 38
        let scroll = NSScrollView(frame: CGRect(
            x: 14, y: footerH + 7,
            width: width - 28, height: height - 35 - footerH - 14
        ))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0, width: scroll.contentSize.width,
            height: scroll.contentSize.height
        ))
        textView.isEditable = false
        textView.isSelectable = !loading
        textView.drawsBackground = false
        textView.font = BTFont.sans(13)
        textView.textColor = loading
            ? NSColor(BTTheme.tertiary) : NSColor(BTTheme.primary)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.string = translation
        scroll.documentView = textView
        root.addSubview(scroll)

        let bottomRule = NSView(frame: CGRect(
            x: 0, y: footerH - 1, width: width, height: 1))
        bottomRule.wantsLayer = true
        bottomRule.layer?.backgroundColor = NSColor(BTTheme.hairline).cgColor
        root.addSubview(bottomRule)

        var buttonX: CGFloat = 10
        func addButton(
            symbol: String,
            tip: String,
            enabled: Bool = true,
            action: @escaping () -> Void
        ) {
            let button = PanelIconButton(symbol: symbol, tip: tip, action: action)
            button.frame.origin = CGPoint(x: buttonX, y: 5)
            button.isEnabled = enabled
            root.addSubview(button)
            buttonX += 30
        }
        addButton(symbol: "doc.on.doc", tip: "Copy bản dịch", enabled: !loading) {
            Self.copy(translation)
        }
        if !source.isEmpty {
            addButton(symbol: "doc.plaintext", tip: "Copy bản gốc", enabled: !loading) {
                Self.copy(source)
            }
        }
        addButton(symbol: "speaker.wave.2", tip: "Đọc bản dịch", enabled: !loading) {
            BTSpeech.toggle(translation, lang: Settings.load().targetLang)
        }
        let closeButton = PanelIconButton(
            symbol: "xmark", tip: "Đóng"
        ) { [weak self] in self?.close() }
        closeButton.frame.origin = CGPoint(x: width - 34, y: 5)
        root.addSubview(closeButton)

        if loading {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.frame = CGRect(x: width - 30, y: height - 29, width: 16, height: 16)
            spinner.startAnimation(nil)
            root.addSubview(spinner)
        }

        win.contentView = root
        win.orderFront(nil)
        window = win
        dismissWatcher = DismissWatcher(frames: [win.frame]) { [weak self, weak win] in
            guard self?.window === win else { return }
            self?.close()
        }
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private final class PanelIconButton: NSButton {
    private let onClick: () -> Void

    init(symbol: String, tip: String, action: @escaping () -> Void) {
        onClick = action
        super.init(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.clear.cgColor
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: tip
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        contentTintColor = NSColor(BTTheme.primary)
        toolTip = tip
        target = self
        self.action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { onClick() }
}
