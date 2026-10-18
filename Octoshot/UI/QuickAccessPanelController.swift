import AppKit
import SwiftUI
import OctoshotCore

private struct QuickAccessDragOverlayEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var quickAccessDragOverlayEnabled: Bool {
        get { self[QuickAccessDragOverlayEnabledKey.self] }
        set { self[QuickAccessDragOverlayEnabledKey.self] = newValue }
    }
}

private struct QuickAccessPanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension QuickAccessStackGeometry.CollapsedStackAnchor {
    var swiftUIAlignment: Alignment {
        switch self {
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        }
    }
}

struct QuickAccessActions {
    var onCopy: () -> Void
    var onSave: () -> Void
    var onAnnotate: () -> Void
    var onPin: () -> Void
    var onOCR: () -> Void
    var onAskAI: (() -> Void)?
    var onCopyMarkdown: (() -> Void)?
    var onCopyPath: (() -> Void)?
    var onClose: () -> Void
}

@MainActor
final class QuickAccessEntry: Identifiable {
    let id = UUID()
    let image: NSImage
    let actions: QuickAccessActions
    let speculativeState: SpeculativeActionState

    init(image: NSImage, actions: QuickAccessActions) {
        self.image = image
        self.actions = actions
        self.speculativeState = SpeculativeActionState()
    }
}

@MainActor
final class QuickAccessStackPresentation: ObservableObject {
    @Published private(set) var stack = QuickAccessCaptureStack()

    func prepend(_ id: QuickAccessStackItemID) {
        var next = stack
        next.prepend(id)
        stack = next
    }

    func syncItemIDs(_ ids: [QuickAccessStackItemID]) {
        var next = stack
        next.syncItemIDs(ids)
        stack = next
    }

    @discardableResult
    func dismissItem(_ id: QuickAccessStackItemID) -> Bool {
        var next = stack
        let isEmpty = next.dismissItem(id)
        stack = next
        return isEmpty
    }

    func expand() {
        var next = stack
        next.expand()
        stack = next
    }

    func collapse() {
        var next = stack
        next.collapse()
        stack = next
    }

    func clear() {
        stack = QuickAccessCaptureStack()
    }

    func setStackCapturesEnabled(_ enabled: Bool) {
        var next = stack
        next.stackCapturesEnabled = enabled
        stack = next
    }
}

@MainActor
final class QuickAccessPanelController: NSObject {
    private var panel: NSPanel?
    private var entries: [QuickAccessEntry] = []
    private let stackPresentation = QuickAccessStackPresentation()
    private var outsideClickMonitors: [Any] = []
    private var autoCloseTimer: Timer?
    private var screenTracker = QuickAccessPanelScreenTracker()
    private var placementObserver: NSObjectProtocol?

    private let maxThumbWidth: CGFloat = 240
    private let maxThumbHeight: CGFloat = 180
    private let maxStackCount = 6

    override init() {
        super.init()
        placementObserver = NotificationCenter.default.addObserver(
            forName: .octoshotQuickAccessPlacementDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionIfNeeded() }
        }
    }

    deinit {
        if let placementObserver {
            NotificationCenter.default.removeObserver(placementObserver)
        }
    }

    func show(image: NSImage, actions: QuickAccessActions, captureAnchor: CGPoint?) {
        screenTracker.screenForNewCapture(
            screens: screenInfos,
            capturePoint: captureAnchor,
            mousePoint: NSEvent.mouseLocation
        )
        let entry = QuickAccessEntry(image: image, actions: actions)
        entries.insert(entry, at: 0)
        stackPresentation.prepend(QuickAccessStackItemID(entry.id))
        stackPresentation.setStackCapturesEnabled(AppSettings.shared.quickAccessStackCaptures)
        if entries.count > maxStackCount {
            let removed = entries.suffix(from: maxStackCount)
            removed.forEach { SpeculativeCapturePipeline.shared.cancel(entryID: $0.id) }
            entries.removeLast(entries.count - maxStackCount)
            stackPresentation.syncItemIDs(entries.map { QuickAccessStackItemID($0.id) })
        }
        SpeculativeCapturePipeline.shared.start(entryID: entry.id, image: image, state: entry.speculativeState)
        rebuildPanel()
        scheduleAutoCloseIfNeeded()
    }

    func closePanel() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        SpeculativeCapturePipeline.shared.cancelAll()
        entries.removeAll()
        stackPresentation.clear()
        removeOutsideClickMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    private func removeEntry(id: UUID) {
        SpeculativeCapturePipeline.shared.cancel(entryID: id)
        entries.removeAll { $0.id == id }
        if stackPresentation.dismissItem(QuickAccessStackItemID(id)) {
            closePanel()
        } else {
            rebuildPanel()
        }
    }

    private func cancelSpeculative(for entry: QuickAccessEntry) {
        SpeculativeCapturePipeline.shared.cancel(entryID: entry.id)
        entry.speculativeState.phase = .hidden
    }

    private func repositionIfNeeded() {
        guard let panel else { return }
        position(panel: panel, size: panel.frame.size)
    }

    private func rebuildPanel() {
        let settings = AppSettings.shared
        stackPresentation.setStackCapturesEnabled(settings.quickAccessStackCaptures)

        let root = QuickAccessStackView(
            entries: entries,
            stackPresentation: stackPresentation,
            placement: settings.quickAccessPlacement,
            maxThumbWidth: maxThumbWidth,
            maxThumbHeight: maxThumbHeight,
            maxExpandedHeight: max(1, (screenTracker.screenForReposition(screens: screenInfos)?.visibleFrame.height ?? 900) - 104),
            onDismissEntry: { [weak self] id in self?.removeEntry(id: id) },
            onDismissAll: { [weak self] in self?.closePanel() },
            onUserChoseAlternateAction: { [weak self] entry in
                self?.cancelSpeculative(for: entry)
            },
            onContentSizeChange: { [weak self] size in
                self?.applyPanelContentSize(size)
            },
            onStackExpandedChange: { [weak self] expanded in
                self?.handleStackExpandedChange(expanded)
            }
        )

        let hosting = NSHostingView(rootView: root)
        let fitting = hosting.fittingSize
        let size = Self.clampedPanelSize(from: fitting, maxThumbWidth: maxThumbWidth)

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                backing: .buffered,
                defer: false
            )
            FullScreenOverlaySupport.configureFloatingOverlayPanel(panel)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            self.panel = panel
        }

        panel?.contentView = hosting
        panel?.setContentSize(size)
        if let panel {
            position(panel: panel, size: size)
            panel.orderFrontRegardless()
        }
    }

    private func applyPanelContentSize(_ contentSize: CGSize) {
        guard let panel else { return }
        let size = Self.clampedPanelSize(from: contentSize, maxThumbWidth: maxThumbWidth)
        let current = panel.frame.size
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
        panel.setContentSize(size)
        position(panel: panel, size: size)
    }

    private static func clampedPanelSize(from fitting: CGSize, maxThumbWidth: CGFloat) -> NSSize {
        NSSize(
            width: min(max(fitting.width, 120), maxThumbWidth + 64),
            height: fitting.height
        )
    }

    private func position(panel: NSPanel, size: NSSize) {
        guard let screen = screenTracker.screenForReposition(screens: screenInfos) else { return }
        let margin: CGFloat = 16
        let origin = QuickAccessPanelGeometry.panelOrigin(
            placement: AppSettings.shared.quickAccessPlacement,
            visibleFrame: screen.visibleFrame,
            panelSize: CGSize(width: size.width, height: size.height),
            margin: margin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private var screenInfos: [QuickAccessScreenInfo] {
        NSScreen.screens.map {
            QuickAccessScreenInfo(
                displayID: $0.displayID,
                frame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        }
    }

    private func scheduleAutoCloseIfNeeded() {
        autoCloseTimer?.invalidate()
        let delay = AppSettings.shared.quickAccessAutoCloseSeconds
        guard delay > 0 else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    private func handleStackExpandedChange(_ expanded: Bool) {
        if expanded {
            installOutsideClickMonitors()
        } else {
            removeOutsideClickMonitors()
        }
    }

    private func installOutsideClickMonitors() {
        guard outsideClickMonitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.collapseStackIfClickedOutside() }
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in
            handler(event)
            return event
        }) {
            outsideClickMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: handler) {
            outsideClickMonitors.append(global)
        }
    }

    private func removeOutsideClickMonitors() {
        outsideClickMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideClickMonitors.removeAll()
    }

    private func collapseStackIfClickedOutside() {
        guard stackPresentation.stack.isExpanded, let panel else { return }
        let click = NSEvent.mouseLocation
        if panel.frame.contains(click) {
            return
        }
        stackPresentation.collapse()
    }

    static func aspectFitSize(for image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        QuickAccessThumbnailSizing.aspectFit(
            imageSize: image.size,
            maxSize: CGSize(width: maxWidth, height: maxHeight)
        )
    }
}

struct QuickAccessStackView: View {
    let entries: [QuickAccessEntry]
    @ObservedObject var stackPresentation: QuickAccessStackPresentation
    let placement: QuickAccessPlacement
    let maxThumbWidth: CGFloat
    let maxThumbHeight: CGFloat
    var maxExpandedHeight: CGFloat = 796
    var animatesAppearance: Bool = true
    let onDismissEntry: (UUID) -> Void
    let onDismissAll: () -> Void
    let onUserChoseAlternateAction: (QuickAccessEntry) -> Void
    let onContentSizeChange: (CGSize) -> Void
    let onStackExpandedChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isStackHovering = false
    @State private var panelAppeared = false

    private var useCollapsedStack: Bool {
        stackPresentation.stack.showsCollapsedStack
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 10) {
            if entries.count > 1 {
                stackHeader
            }

            if useCollapsedStack {
                collapsedStack
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: collapseTransitionAnchor)))
            } else {
                expandedList
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: useCollapsedStack)
        // No outer container: thumbnails float directly on the desktop (Finder-stack style).
        // The transparent padding only leaves room for card shadows and the 3D lift.
        .padding(16)
        .scaleEffect(panelAppeared || reduceMotion || !animatesAppearance ? 1 : 0.94)
        .opacity(panelAppeared || reduceMotion || !animatesAppearance ? 1 : 0)
        .onAppear {
            guard !reduceMotion, animatesAppearance else {
                panelAppeared = true
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                panelAppeared = true
            }
        }
        .onChange(of: stackPresentation.stack.isExpanded) { _, expanded in
            onStackExpandedChange(expanded)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: QuickAccessPanelSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(QuickAccessPanelSizeKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            onContentSizeChange(size)
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch placement {
        case .bottomLeft, .leftSidebar:
            return .leading
        case .bottomRight, .rightSidebar:
            return .trailing
        }
    }

    private var collapseTransitionAnchor: UnitPoint {
        switch placement {
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        case .leftSidebar:
            return .topLeading
        case .rightSidebar:
            return .topTrailing
        }
    }

    @ViewBuilder
    private var stackHeader: some View {
        stackHeaderButtons
            .padding(.horizontal, stackHeaderHasButtons ? 10 : 0)
            .padding(.vertical, stackHeaderHasButtons ? 5 : 0)
            .background {
                if stackHeaderHasButtons {
                    Capsule().fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                }
            }
    }

    private var stackHeaderHasButtons: Bool {
        stackPresentation.stack.isExpanded || isStackHovering || !useCollapsedStack
    }

    @ViewBuilder
    private var stackHeaderButtons: some View {
        HStack(spacing: 10) {
            if stackPresentation.stack.isExpanded {
                Button(action: collapseStack) {
                    Label(OctoshotL10n.quickAccessCollapseStack, systemImage: "rectangle.arrowtriangle.2.inward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(OctoshotL10n.quickAccessCollapseStack)
            }
            if stackPresentation.stack.isExpanded || isStackHovering || !useCollapsedStack {
                Button(action: onDismissAll) {
                    Label(OctoshotL10n.quickAccessCloseAll, systemImage: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(OctoshotL10n.quickAccessCloseAll)
            }
        }
    }

    @ViewBuilder
    private var expandedList: some View {
        let height = entries.reduce(CGFloat(0)) { total, entry in
            total + QuickAccessPanelController.aspectFitSize(
                for: entry.image, maxWidth: maxThumbWidth, maxHeight: maxThumbHeight
            ).height
        } + CGFloat(max(0, entries.count - 1)) * 10
        if height > maxExpandedHeight {
            ScrollView(.vertical) {
                expandedCards
            }
            .frame(width: maxThumbWidth, height: maxExpandedHeight)
        } else {
            expandedCards
        }
    }

    private var expandedCards: some View {
        VStack(alignment: horizontalAlignment, spacing: 10) {
            ForEach(entries) { entry in
                QuickAccessCard(
                    entry: entry,
                    placement: placement,
                    thumbSize: QuickAccessPanelController.aspectFitSize(
                        for: entry.image,
                        maxWidth: maxThumbWidth,
                        maxHeight: maxThumbHeight
                    ),
                    onClose: { onDismissEntry(entry.id) },
                    onAlternateAction: { onUserChoseAlternateAction(entry) },
                    onDragSucceeded: { onDismissEntry(entry.id) }
                )
                .frame(width: maxThumbWidth, alignment: cardFrameAlignment)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: entries.map(\.id))
    }

    private var collapsedStack: some View {
        let sizes = entries.map {
            QuickAccessPanelController.aspectFitSize(
                for: $0.image, maxWidth: maxThumbWidth, maxHeight: maxThumbHeight
            )
        }
        let frames = QuickAccessStackGeometry.collapsedCardFrames(sizes: sizes, placement: placement)
        let bounds = frames.reduce(CGRect.null) { $0.union($1) }

        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated().reversed()), id: \.element.id) { index, entry in
                if index < QuickAccessStackGeometry.maxCollapsedLayers {
                    let thumbSize = QuickAccessPanelController.aspectFitSize(
                        for: entry.image,
                        maxWidth: maxThumbWidth,
                        maxHeight: maxThumbHeight
                    )
                    QuickAccessCard(
                        entry: entry,
                        placement: placement,
                        thumbSize: thumbSize,
                        onClose: { onDismissEntry(entry.id) },
                        onAlternateAction: { onUserChoseAlternateAction(entry) },
                        onDragSucceeded: index == 0 ? { onDismissEntry(entry.id) } : nil,
                        onThumbnailClick: index == 0 ? { expandStackIfNeeded() } : nil,
                        showsActionsOnHover: index == 0
                    )
                    .overlay(alignment: stackBadgeAlignment) {
                        if index == 0, entries.count > 1 {
                            stackCountBadge
                        }
                    }
                    .offset(x: frames[index].minX, y: frames[index].minY)
                    .zIndex(QuickAccessStackGeometry.collapsedZIndex(index: index, total: entries.count))
                    .allowsHitTesting(index == 0)
                }
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .frame(minWidth: maxThumbWidth, alignment: cardFrameAlignment)
        .padding(.top, 44)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: entries.count)
        .contentShape(Rectangle())
        .onHover { hovering in
            isStackHovering = hovering
        }
        .onTapGesture {
            expandStackIfNeeded()
        }
    }

    private var stackCountBadge: some View {
        Text("\(entries.count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .padding(6)
            .allowsHitTesting(false)
    }

    private var cardFrameAlignment: Alignment {
        placement == .bottomLeft || placement == .leftSidebar ? .leading : .trailing
    }

    private var stackBadgeAlignment: Alignment {
        switch placement {
        case .bottomLeft, .leftSidebar:
            return .topLeading
        case .bottomRight, .rightSidebar:
            return .topTrailing
        }
    }

    private func expandStackIfNeeded() {
        guard !stackPresentation.stack.isExpanded else { return }
        if reduceMotion {
            stackPresentation.expand()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                stackPresentation.expand()
            }
        }
    }

    private func collapseStack() {
        guard stackPresentation.stack.isExpanded else { return }
        if reduceMotion {
            stackPresentation.collapse()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                stackPresentation.collapse()
            }
        }
    }
}

private struct QuickAccessCard: View {
    @ObservedObject var speculativeState: SpeculativeActionState
    let entry: QuickAccessEntry
    let placement: QuickAccessPlacement
    let thumbSize: NSSize
    let onClose: () -> Void
    let onAlternateAction: () -> Void
    var onDragSucceeded: (() -> Void)?
    var onThumbnailClick: (() -> Void)?
    var showsActionsOnHover: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quickAccessDragOverlayEnabled) private var dragOverlayEnabled
    @State private var isHovering = false

    init(
        entry: QuickAccessEntry,
        placement: QuickAccessPlacement,
        thumbSize: NSSize,
        onClose: @escaping () -> Void,
        onAlternateAction: @escaping () -> Void,
        onDragSucceeded: (() -> Void)? = nil,
        onThumbnailClick: (() -> Void)? = nil,
        showsActionsOnHover: Bool = true
    ) {
        self.entry = entry
        self.placement = placement
        self.speculativeState = entry.speculativeState
        self.thumbSize = thumbSize
        self.onClose = onClose
        self.onAlternateAction = onAlternateAction
        self.onDragSucceeded = onDragSucceeded
        self.onThumbnailClick = onThumbnailClick
        self.showsActionsOnHover = showsActionsOnHover
    }

    var body: some View {
        QuickAccessThumbnailChrome(isHovering: showsActionsOnHover && isHovering, reduceMotion: reduceMotion) {
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbSize.width, height: thumbSize.height)
                .overlay {
                    if dragOverlayEnabled {
                        DraggableThumbnailView(
                            image: entry.image,
                            size: thumbSize,
                            onClick: onThumbnailClick,
                            onDragEnded: { operation in
                                if QuickAccessDragOutcome.fromEndedDragOperation(operation) == .removeFromStack {
                                    onDragSucceeded?()
                                }
                            }
                        )
                        .frame(width: thumbSize.width, height: thumbSize.height)
                    }
                }
        }
        .overlay(alignment: dismissButtonAlignment) {
            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.45))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help(OctoshotL10n.quickAccessDismissCapture)
                .padding(6)
                .transition(.opacity)
            }
        }

        .overlay(alignment: actionOverlayAlignment) {
            if showsActionsOnHover, isHovering {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 6) {
                        QuickAccessButton(
                            symbol: "doc.on.clipboard",
                            label: OctoshotL10n.quickAccessCopy,
                            action: wrapAlternate(entry.actions.onCopy)
                        )
                        QuickAccessButton(
                            symbol: "square.and.arrow.down.fill",
                            label: OctoshotL10n.quickAccessSave,
                            action: wrapAlternate(entry.actions.onSave)
                        )
                        QuickAccessButton(
                            symbol: "pencil.and.outline",
                            label: OctoshotL10n.quickAccessAnnotate,
                            action: wrapAlternate(entry.actions.onAnnotate)
                        )
                        QuickAccessButton(
                            symbol: "pin.circle.fill",
                            label: OctoshotL10n.quickAccessPin,
                            action: wrapAlternate(entry.actions.onPin)
                        )
                        QuickAccessButton(
                            symbol: "text.viewfinder",
                            label: OctoshotL10n.ocrAction,
                            action: wrapAlternate(entry.actions.onOCR)
                        )
                        if let onAskAI = entry.actions.onAskAI {
                            QuickAccessButton(
                                symbol: "sparkles",
                                label: OctoshotL10n.quickAccessAskAI,
                                action: wrapAlternate(onAskAI)
                            )
                        }
                        if let onCopyMarkdown = entry.actions.onCopyMarkdown {
                            QuickAccessButton(
                                symbol: "curlybraces.square",
                                label: OctoshotL10n.quickAccessCopyMarkdown,
                                action: wrapAlternate(onCopyMarkdown)
                            )
                        }
                        if let onCopyPath = entry.actions.onCopyPath {
                            QuickAccessButton(
                                symbol: "link.circle",
                                label: OctoshotL10n.quickAccessCopyPath,
                                action: wrapAlternate(onCopyPath)
                            )
                        }
                        QuickAccessButton(
                            symbol: "xmark.circle.fill",
                            label: OctoshotL10n.quickAccessClose,
                            action: onClose
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(width: 240, height: 52)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: primaryOverlayAlignment) {
            SpeculativePrimaryButton(
                phase: speculativeState.phase,
                onApply: { applySpeculativeResult() }
            )
            .frame(width: 240, height: 36, alignment: primaryOverlayAlignment)
            .clipped()
            .offset(y: -44)
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
    }

    private var actionOverlayAlignment: Alignment {
        placement == .bottomLeft || placement == .leftSidebar ? .bottomLeading : .bottomTrailing
    }

    private var primaryOverlayAlignment: Alignment {
        placement == .bottomLeft || placement == .leftSidebar ? .topLeading : .topTrailing
    }

    private var dismissButtonAlignment: Alignment {
        switch placement {
        case .bottomLeft, .leftSidebar:
            return .topLeading
        case .bottomRight, .rightSidebar:
            return .topTrailing
        }
    }

    private func wrapAlternate(_ action: @escaping () -> Void) -> () -> Void {
        {
            onAlternateAction()
            action()
        }
    }

    private func applySpeculativeResult() {
        guard case .ready(_, let result) = speculativeState.phase else { return }
        switch result {
        case .latex(let text), .tableMarkdown(let text), .codeText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .redactedImage(let image):
            ImageFormats.copyToPasteboard(image)
        }
        onAlternateAction()
        speculativeState.phase = .hidden
    }
}

private struct QuickAccessThumbnailChrome<Content: View>: View {
    let isHovering: Bool
    let reduceMotion: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : (isHovering ? 5 : 1.5)),
                axis: (x: -0.35, y: 1, z: 0),
                perspective: 0.55
            )
            .scaleEffect(reduceMotion || !isHovering ? 1 : 1.025)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.74), value: isHovering)
    }
}

private struct SpeculativePrimaryButton: View {
    let phase: SpeculativeActionState.Phase
    let onApply: () -> Void

    var body: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .classifying:
            pill(label: "Analyzing…", systemImage: "sparkles", progress: true, enabled: false)
        case .running(let kind, let detail):
            pill(label: detail, systemImage: kind.systemImage, progress: true, enabled: false)
        case .ready(let kind, _):
            Button(action: onApply) {
                pillContent(label: "Apply \(kind.displayName)", systemImage: kind.systemImage, progress: false)
            }
            .buttonStyle(.plain)
        case .suggestionOnly(let kind, let reason):
            pill(label: "\(kind.displayName) — \(reason)", systemImage: kind.systemImage, progress: false, enabled: false)
                .opacity(0.75)
        case .failed(let message):
            pill(label: message, systemImage: "exclamationmark.triangle", progress: false, enabled: false)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func pill(label: String, systemImage: String, progress: Bool, enabled: Bool) -> some View {
        HStack(spacing: 8) {
            pillContent(label: label, systemImage: systemImage, progress: progress)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial, in: Capsule())
        .opacity(enabled ? 1 : 0.95)
    }

    private func pillContent(label: String, systemImage: String, progress: Bool) -> some View {
        HStack(spacing: 8) {
            if progress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }
}

private struct QuickAccessButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 18)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(minWidth: 40)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct DraggableThumbnailView: NSViewRepresentable {
    let image: NSImage
    let size: NSSize
    var onClick: (() -> Void)?
    var onDragEnded: (UInt) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDragEnded: onDragEnded, onClick: onClick)
    }

    func makeNSView(context: Context) -> DraggableImageView {
        let view = DraggableImageView()
        view.dragImage = image
        view.onDragEnded = { context.coordinator.reportDragEnded(operation: $0) }
        view.onClick = { context.coordinator.reportClick() }
        return view
    }

    func updateNSView(_ nsView: DraggableImageView, context: Context) {
        nsView.dragImage = image
        nsView.onDragEnded = { context.coordinator.reportDragEnded(operation: $0) }
        nsView.onClick = { context.coordinator.reportClick() }
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.onClick = onClick
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DraggableImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? size.width, height: proposal.height ?? size.height)
    }

    final class Coordinator {
        var onDragEnded: (UInt) -> Void
        var onClick: (() -> Void)?

        init(onDragEnded: @escaping (UInt) -> Void, onClick: (() -> Void)?) {
            self.onDragEnded = onDragEnded
            self.onClick = onClick
        }

        func reportDragEnded(operation: UInt) {
            onDragEnded(operation)
        }

        func reportClick() {
            onClick?()
        }
    }
}

final class DraggableImageView: NSImageView {
    var dragImage: NSImage?
    var onDragEnded: ((UInt) -> Void)?
    var onClick: (() -> Void)?

    private var mouseDownLocation: NSPoint?
    private var didBeginDrag = false
    private let dragThreshold: CGFloat = 5

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {}

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag, let image = dragImage, let start = mouseDownLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance >= dragThreshold else { return }
        didBeginDrag = true
        mouseDownLocation = nil

        let item = NSPasteboardItem()
        if let data = ImageFormats.pngData(from: image) {
            item.setData(data, forType: .png)
        }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginDrag, mouseDownLocation != nil {
            onClick?()
        }
        mouseDownLocation = nil
        didBeginDrag = false
    }
}

extension DraggableImageView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragEnded?(operation.rawValue)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
