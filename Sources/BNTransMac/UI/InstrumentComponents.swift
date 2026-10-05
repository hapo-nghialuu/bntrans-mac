import AppKit
import SwiftUI

// MARK: - Instrument primitives (ported from BirdNion InstrumentComponents)
//
// Square controls, hairline rules, mono eyebrow labels — the shared building
// blocks of the "Instrument" language so every view applies it the same way.

/// Square switch (40×20, 3pt corner): outlined track when off, solid accent
/// when on; small square knob.
struct InstrumentSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn = !configuration.isOn
        } label: {
            InstrumentSwitchTrack(isOn: configuration.isOn)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityAddTraits(.isButton)
    }
}

private struct InstrumentSwitchTrack: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isOn ? BTTheme.accent : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            isOn ? Color.clear : BTTheme.secondary,
                            lineWidth: 1.5)
                )
                .frame(width: 40, height: 20)
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(isOn ? BTTheme.background : BTTheme.primary)
                .frame(width: 14, height: 14)
                .padding(3)
        }
        .frame(width: 40, height: 20)
        .contentShape(Rectangle())
    }
}

extension ToggleStyle where Self == InstrumentSwitchStyle {
    static var instrumentSwitch: InstrumentSwitchStyle { InstrumentSwitchStyle() }
}

/// A single hairline rule — the section separator that replaces filled,
/// rounded card backgrounds.
struct HairlineRule: View {
    var color: Color = BTTheme.hairline
    var body: some View {
        color.frame(height: 1)
    }
}

extension View {
    /// Adds a top hairline divider. `inset` indents the rule from the edges.
    func hairlineTop(_ color: Color = BTTheme.hairline, inset: CGFloat = 0) -> some View {
        overlay(alignment: .top) {
            color.frame(height: 1)
                .padding(.horizontal, inset)
        }
    }

    /// Adds the stronger ink rule below headers.
    func inkRuleBottom(inset: CGFloat = 0) -> some View {
        overlay(alignment: .bottom) {
            BTTheme.inkRule.frame(height: 1)
                .padding(.horizontal, inset)
        }
    }

    /// Uppercase mono eyebrow label (section headers): IBM Plex Mono,
    /// medium weight, wide tracking, tertiary color, upper-cased.
    func plexEyebrow(
        size: CGFloat = 10,
        color: Color = BTTheme.tertiary,
        tracking: CGFloat = 0.8
    ) -> some View {
        self
            .font(.plexMono(size, weight: .medium))
            .tracking(tracking)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}

/// Square hairline-bordered control corner radius used throughout (buttons,
/// inputs, selects) — 4pt square language.
enum InstrumentShape {
    static let controlRadius: CGFloat = 4
}

enum InstrumentMetrics {
    static let controlHeight: CGFloat = 28
    static let iconButtonSize: CGFloat = 28
    static let selectWidth: CGFloat = 170
}

/// Outlined square button (mono uppercase): transparent fill, 1px border,
/// hover fill.
struct InstrumentButtonStyle: ButtonStyle {
    var textColor: Color = BTTheme.secondary
    var borderColor: Color = BTTheme.border

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plexMono(10, weight: .medium))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(textColor)
            .padding(.horizontal, 13)
            .frame(minHeight: InstrumentMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? BTTheme.hoverSurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == InstrumentButtonStyle {
    static var instrumentPrimary: InstrumentButtonStyle {
        InstrumentButtonStyle(textColor: BTTheme.primary, borderColor: BTTheme.primary)
    }
    static var instrumentOutline: InstrumentButtonStyle {
        InstrumentButtonStyle(textColor: BTTheme.secondary, borderColor: BTTheme.border)
    }
    static var instrumentAccent: InstrumentButtonStyle {
        InstrumentButtonStyle(textColor: BTTheme.accent, borderColor: BTTheme.border)
    }
}

/// Inline action button (Save / Refresh) — 28pt tall to sit flush with
/// fields and selects. `prominent` = accent fill + paper label.
struct InstrumentInlineButtonStyle: ButtonStyle {
    var prominent: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = prominent ? BTTheme.background : BTTheme.accent
        configuration.label
            .font(.plexMono(11, weight: .medium))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .fill(prominent ? BTTheme.accent : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : BTTheme.accent, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == InstrumentInlineButtonStyle {
    static var instrumentInline: InstrumentInlineButtonStyle { InstrumentInlineButtonStyle() }
}

extension View {
    /// Square hairline field — 28pt min height, 4pt radius, paper fill,
    /// 1px border. Replaces `.textFieldStyle(.roundedBorder)`.
    func instrumentControlFieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(BTTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .strokeBorder(BTTheme.border, lineWidth: 1)
            )
    }
}

// MARK: - Menu select

/// Tallest the dropdown may grow before it scrolls.
private let instrumentMenuMaxPanelHeight: CGFloat = 360

/// Option list hosted inside the borderless AppKit menu panel.
private struct InstrumentMenuPanelContent<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    let selection: Value
    let width: CGFloat
    let onPick: (Value) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    if index > 0 {
                        BTTheme.hairline.frame(height: 1)
                    }
                    Button {
                        onPick(option.value)
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title)
                                .font(.plexSans(12))
                                .foregroundStyle(BTTheme.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if option.value == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(BTTheme.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(option.value == selection
                                    ? BTTheme.selectedSurface
                                    : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
        .background(BTTheme.background)
        .overlay(
            RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                .strokeBorder(BTTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous))
    }
}

/// Presents the option list in a borderless child `NSPanel` so sibling
/// SwiftUI rows cannot paint over it. No NSPopover arrow / system chrome.
private struct InstrumentMenuPanelBridge<Value: Hashable>: NSViewRepresentable {
    @Binding var isOpen: Bool
    @Binding var selection: Value
    var options: [(value: Value, title: String)]

    func makeCoordinator() -> Coordinator {
        Coordinator(isOpen: $isOpen, selection: $selection, options: options)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.identifier = NSUserInterfaceItemIdentifier("bt-select-anchor")
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.isOpen = $isOpen
        context.coordinator.selection = $selection
        context.coordinator.options = options
        if isOpen {
            context.coordinator.showOrUpdate()
        } else {
            context.coordinator.hide()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hide()
    }

    @MainActor final class Coordinator {
        var isOpen: Binding<Bool>
        var selection: Binding<Value>
        var options: [(value: Value, title: String)]
        weak var anchorView: NSView?
        private var panel: NSPanel?
        private var hosting: NSHostingView<InstrumentMenuPanelContent<Value>>?
        private var monitor: Any?
        private var openGeneration = 0
        private var showRetries = 0

        init(isOpen: Binding<Bool>,
             selection: Binding<Value>,
             options: [(value: Value, title: String)]) {
            self.isOpen = isOpen
            self.selection = selection
            self.options = options
        }

        func showOrUpdate() {
            guard let anchor = anchorView else { return }
            guard anchor.window != nil else {
                // SwiftUI can run updateNSView while the representable is
                // detached (initial layout, reparent during a state change).
                // Retry briefly instead of dropping the open request — this
                // is the race that left the dropdown invisible after a click.
                scheduleShowRetry()
                return
            }
            showRetries = 0
            if panel == nil {
                present(from: anchor)
            } else {
                refreshContent(anchorWidth: anchor.bounds.width)
                reposition(from: anchor)
            }
        }

        private func scheduleShowRetry() {
            showRetries += 1
            guard showRetries <= 90 else { // ~1.5s ceiling
                showRetries = 0
                return
            }
            let attempt = showRetries
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                guard let self, self.isOpen.wrappedValue,
                      self.showRetries == attempt else { return }
                self.showOrUpdate()
            }
        }

        func hide() {
            showRetries = 0
            removeMonitor()
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
            hosting = nil
        }

        private func panelSize(
            fittingHeight: CGFloat, width: CGFloat, anchor: NSView
        ) -> NSSize {
            // Cap growth so long option lists scroll instead of running off
            // the screen edge (OpenRouter returns 400+ models).
            var available = instrumentMenuMaxPanelHeight
            if let screen = anchor.window?.screen {
                let rect = anchor.convert(anchor.bounds, to: nil)
                let screenRect = anchor.window!.convertToScreen(rect)
                let vis = screen.visibleFrame
                let below = screenRect.minY - vis.minY - 8
                let above = vis.maxY - screenRect.maxY - 8
                available = max(
                    140, min(instrumentMenuMaxPanelHeight, max(below, above)))
            }
            return NSSize(width: width, height: min(fittingHeight, available))
        }

        private func present(from anchor: NSView) {
            guard let parentWindow = anchor.window else { return }
            let width = max(anchor.bounds.width, 180)
            let root = makeContent(width: width)
            let host = NSHostingView(rootView: root)
            host.appearance = NSApp.effectiveAppearance
            let size = panelSize(
                fittingHeight: host.fittingSize.height, width: width, anchor: anchor)
            host.frame = NSRect(origin: .zero, size: size)

            let newPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false)
            newPanel.isOpaque = true
            newPanel.hasShadow = true
            newPanel.level = .popUpMenu
            newPanel.isFloatingPanel = true
            newPanel.hidesOnDeactivate = true
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.appearance = NSApp.effectiveAppearance
            newPanel.backgroundColor = .clear
            newPanel.contentView = host
            newPanel.isReleasedWhenClosed = false

            hosting = host
            panel = newPanel
            reposition(from: anchor)
            parentWindow.addChildWindow(newPanel, ordered: .above)
            newPanel.orderFront(nil)

            openGeneration += 1
            let generation = openGeneration
            // Skip the mouse-down that opened the menu.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.openGeneration == generation else { return }
                self.installMonitor()
            }
        }

        private func refreshContent(anchorWidth: CGFloat) {
            let width = max(anchorWidth, 180)
            hosting?.rootView = makeContent(width: width)
            guard let hosting, let panel, let anchor = anchorView else { return }
            let size = panelSize(
                fittingHeight: hosting.fittingSize.height, width: width, anchor: anchor)
            hosting.frame = NSRect(origin: .zero, size: size)
            var frame = panel.frame
            frame.size = size
            panel.setFrame(frame, display: true)
        }

        private func makeContent(width: CGFloat) -> InstrumentMenuPanelContent<Value> {
            InstrumentMenuPanelContent(
                options: options,
                selection: selection.wrappedValue,
                width: width,
                onPick: { [weak self] value in
                    guard let self else { return }
                    self.selection.wrappedValue = value
                    self.isOpen.wrappedValue = false
                    self.hide()
                })
        }

        private func reposition(from anchor: NSView) {
            guard let panel, let parentWindow = anchor.window else { return }
            let rectInWindow = anchor.convert(anchor.bounds, to: nil)
            let screenRect = parentWindow.convertToScreen(rectInWindow)
            let size = panel.frame.size
            // Open downward by default; flip above the trigger when the
            // space below cannot hold the panel but the space above can.
            var y = screenRect.minY - 4 - size.height
            if let vis = parentWindow.screen?.visibleFrame {
                let below = screenRect.minY - vis.minY - 4
                let above = vis.maxY - screenRect.maxY - 4
                if below < size.height, above > below {
                    y = screenRect.maxY + 4
                }
            }
            let origin = NSPoint(x: screenRect.minX, y: y)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.isOpen.wrappedValue else { return event }
                if let panel = self.panel, event.window === panel {
                    return event
                }
                DispatchQueue.main.async {
                    self.isOpen.wrappedValue = false
                    self.hide()
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// Settings select — trigger chrome matches `instrumentControlFieldStyle`.
/// Options open in a borderless AppKit panel (Instrument 4pt, no arrow).
struct InstrumentMenuSelect<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    @State private var isOpen: Bool

    init(
        options: [(value: Value, title: String)],
        selection: Binding<Value>,
        debugOpen: Bool = false
    ) {
        self.options = options
        self._selection = selection
        self._isOpen = State(initialValue: debugOpen)
    }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? "—"
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selectedTitle)
                    .font(.plexSans(12))
                    .foregroundStyle(BTTheme.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BTTheme.tertiary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(BTTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: InstrumentShape.controlRadius, style: .continuous)
                    .strokeBorder(isOpen ? BTTheme.primary : BTTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .background {
            InstrumentMenuPanelBridge(
                isOpen: $isOpen,
                selection: $selection,
                options: options)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Cursor

private struct PointingHandCursorModifier: ViewModifier {
    let enabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside, enabled, !isHovering {
                isHovering = true
                NSCursor.pointingHand.push()
            } else if !inside, isHovering {
                isHovering = false
                NSCursor.pop()
            }
            if !enabled, isHovering {
                isHovering = false
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                isHovering = false
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(enabled: enabled))
    }
}
