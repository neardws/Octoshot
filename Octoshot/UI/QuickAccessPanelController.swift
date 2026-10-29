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

struct QuickAccessActions {
    var onCopy: (@escaping () -> Void) -> Void
    var onSave: (@escaping () -> Void) -> Void
    var onAnnotate: () -> Void
    var onPin: () -> Void
    var onOCR: () -> Void
    var onAskAI: (() -> Void)?
    var onCopyMarkdown: ((@escaping () -> Void) -> Void)?
    var onCopyPath: ((@escaping () -> Void) -> Void)?
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
            toolbarStyle: settings.quickAccessToolbarStyle,
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
            width: min(max(fitting.width, 120), maxThumbWidth + QuickAccessLayout.padding * 2),
            height: fitting.height
        )
    }

    private func position(panel: NSPanel, size: NSSize) {
        guard let screen = screenTracker.screenForReposition(screens: screenInfos) else { return }
        let margin: CGFloat = 16
        let placement = AppSettings.shared.quickAccessPlacement
        let origin = QuickAccessPanelGeometry.panelOrigin(
            placement: placement == .leftSidebar ? .bottomLeft : placement == .rightSidebar ? .bottomRight : placement,
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

#if DEBUG
private struct QuickAccessSnapshotStateKey: EnvironmentKey {
    static let defaultValue = QuickAccessSnapshotState()
}

struct QuickAccessSnapshotState {
    var hoveredID: UUID?
    var progress: CGFloat?
}

extension EnvironmentValues {
    var quickAccessSnapshotState: QuickAccessSnapshotState {
        get { self[QuickAccessSnapshotStateKey.self] }
        set { self[QuickAccessSnapshotStateKey.self] = newValue }
    }
}
#endif

struct QuickAccessStackView: View {
    let entries: [QuickAccessEntry]
    @ObservedObject var stackPresentation: QuickAccessStackPresentation
    let placement: QuickAccessPlacement
    let maxThumbWidth: CGFloat
    let maxThumbHeight: CGFloat
    var maxExpandedHeight: CGFloat = 796
    var animatesAppearance: Bool = true
    var toolbarStyle: QuickAccessToolbarStyle = .below
    let onDismissEntry: (UUID) -> Void
    let onDismissAll: () -> Void
    let onUserChoseAlternateAction: (QuickAccessEntry) -> Void
    let onContentSizeChange: (CGSize) -> Void
    let onStackExpandedChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visualExpanded = false
    @State private var reservesExpandedSpace = false
    @State private var hoveredID: UUID?
    @State private var canvasViewportOrigin: CGPoint = .zero
    @ObservedObject private var settings = AppSettings.shared
#if DEBUG
    @Environment(\.quickAccessSnapshotState) private var snapshotState
#endif

    private var targetExpanded: Bool { !stackPresentation.stack.showsCollapsedStack }
    private var selectedToolbarStyle: QuickAccessToolbarStyle {
        animatesAppearance ? settings.quickAccessToolbarStyle : toolbarStyle
    }
    private var expanded: Bool { animatesAppearance ? visualExpanded : targetExpanded }
    private var sizes: [CGSize] {
        entries.map {
            QuickAccessPanelController.aspectFitSize(for: $0.image, maxWidth: maxThumbWidth, maxHeight: maxThumbHeight)
        }
    }
    private var canvasSize: CGSize {
        if reservesExpandedSpace || expanded {
            let collapsed = reservedSize(expanded: false)
            let expanded = reservedSize(expanded: true)
            return CGSize(width: max(collapsed.width, expanded.width), height: max(collapsed.height, expanded.height))
        }
        return reservedSize(expanded: false)
    }
    private func reservedSize(expanded: Bool) -> CGSize {
        QuickAccessLayout.reservedContentSize(sizes: sizes, expanded: expanded,
                                              placement: placement, style: selectedToolbarStyle)
    }
    private var visibleSize: CGSize {
        CGSize(width: canvasSize.width, height: min(canvasSize.height, maxExpandedHeight))
    }
    private var frames: [CGRect] {
#if DEBUG
        if let progress = snapshotState.progress {
            return sizes.indices.map { index in
                let time = min(1, max(0, (progress * 0.85 - CGFloat(index) * 0.03) / 0.65))
                return QuickAccessLayout.presentedFrames(sizes: sizes, placement: placement,
                    progress: QuickAccessLayout.springProgress(time), canvasHeight: canvasSize.height,
                    hoveredIndex: entries.firstIndex { $0.id == activeHover }, style: selectedToolbarStyle)[index]
            }
        }
#endif
        return QuickAccessLayout.presentedFrames(sizes: sizes, placement: placement,
            progress: expanded ? 1 : 0, canvasHeight: canvasSize.height,
            hoveredIndex: entries.firstIndex { $0.id == activeHover }, style: selectedToolbarStyle)
    }
    private var activeHover: UUID? {
#if DEBUG
        if let forced = snapshotState.hoveredID { return forced }
#endif
        return hoveredID
    }

    var body: some View {
        viewport
        .coordinateSpace(name: "quickAccessViewport")
        .task(id: targetExpanded) {
            onStackExpandedChange(stackPresentation.stack.isExpanded)
            hoveredID = nil
            if reduceMotion || !animatesAppearance {
                visualExpanded = targetExpanded
                reservesExpandedSpace = targetExpanded
                onContentSizeChange(visibleSize)
                return
            }
            if targetExpanded {
                reservesExpandedSpace = true
                let collapsed = reservedSize(expanded: false)
                let expanded = reservedSize(expanded: true)
                let union = CGSize(width: max(collapsed.width, expanded.width), height: max(collapsed.height, expanded.height))
                onContentSizeChange(CGSize(width: union.width, height: min(union.height, maxExpandedHeight)))
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                visualExpanded = true
            } else {
                visualExpanded = false
                try? await Task.sleep(for: .milliseconds(1000))
                guard !Task.isCancelled else { return }
                reservesExpandedSpace = false
                onContentSizeChange(visibleSize)
            }
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

    @ViewBuilder
    private var viewport: some View {
        if !animatesAppearance {
            canvas
        } else {
            ScrollViewReader { scroll in
                ScrollView(.vertical, showsIndicators: canvasSize.height > maxExpandedHeight) {
                    canvas
                        .overlay(alignment: .bottom) { Color.clear.frame(height: 1).id("bottom") }
                }
                .defaultScrollAnchor(.bottom)
                .scrollClipDisabled()
                .frame(width: visibleSize.width, height: visibleSize.height)
                .onChange(of: canvasSize) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let frame = frames[index]
                QuickAccessCard(
                    entry: entry, placement: placement, thumbSize: sizes[index],
                    onClose: { onDismissEntry(entry.id) },
                    onAlternateAction: { onUserChoseAlternateAction(entry) },
                    onDragSucceeded: { onDismissEntry(entry.id) },
                    onThumbnailClick: { if !expanded { stackPresentation.expand() } },
                    showsActionsOnHover: expanded || index == 0,
                    toolbarStyle: selectedToolbarStyle, isHovering: activeHover == entry.id,
                    viewportSize: visibleSize
                )
                .frame(width: sizes[index].width, height: sizes[index].height)
                .scaleEffect(frame.width / sizes[index].width, anchor: .topLeading)
                .offset(x: frame.minX, y: frame.minY)
                .opacity(expanded || index < QuickAccessStackGeometry.maxCollapsedLayers ? 1 : 0)
                .zIndex(activeHover == entry.id ? Double(entries.count + (selectedToolbarStyle == .bubbles ? 3 : 1)) : Double(entries.count - index))
                .allowsHitTesting(expanded || index == 0)
                .animation(reduceMotion || !animatesAppearance ? nil :
                    .easeOut(duration: 0.3).delay(Double(index) * 0.03), value: expanded)
                .animation(reduceMotion || !animatesAppearance ? nil :
                    .easeOut(duration: 0.2), value: activeHover)
            }
            if entries.count > 1 {
                let top = frames.prefix(expanded ? entries.count : QuickAccessStackGeometry.maxCollapsedLayers)
                    .min { $0.minY < $1.minY } ?? .zero
                header
                    .frame(width: top.width, alignment: .trailing)
                    .offset(x: top.minX, y: top.minY - 32)
                    .zIndex(Double(entries.count + 2))
                    .animation(reduceMotion || !animatesAppearance ? nil :
                        .easeOut(duration: 0.3).delay(Double(entries.count - 1) * 0.03), value: expanded)
                    .animation(reduceMotion || !animatesAppearance ? nil :
                        .easeOut(duration: 0.2), value: activeHover)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .onGeometryChange(for: CGPoint.self) { proxy in
            proxy.frame(in: .named("quickAccessViewport")).origin
        } action: { origin in
            canvasViewportOrigin = origin
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !expanded { stackPresentation.expand() }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): updateHover(at: point)
            case .ended: hoveredID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(entries.count)").font(.system(size: 11, weight: .bold, design: .rounded))
            if expanded {
                Button(action: { stackPresentation.collapse() }) {
                    Image(systemName: "rectangle.arrowtriangle.2.inward")
                }
                .help(OctoshotL10n.quickAccessCollapseStack)
                .accessibilityLabel(OctoshotL10n.quickAccessCollapseStack)
            }
            Button(action: onDismissAll) { Image(systemName: "xmark") }
                .help(OctoshotL10n.quickAccessCloseAll)
                .accessibilityLabel(OctoshotL10n.quickAccessCloseAll)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private func updateHover(at point: CGPoint) {
        let eligible = expanded ? Array(entries.indices) : Array(entries.indices.prefix(1))
        if let current = eligible.first(where: { entries[$0].id == hoveredID }) {
            let frame = frames[current]
            let resting = QuickAccessLayout.presentedFrames(sizes: sizes, placement: placement,
                progress: expanded ? 1 : 0, canvasHeight: canvasSize.height,
                hoveredIndex: nil, style: selectedToolbarStyle)[current]
            if frame.union(resting).contains(point) { return }
            if !frame.contains(point), QuickAccessLayout.toolbarContains(
                point, imageRect: frame, style: selectedToolbarStyle, placement: placement,
                visibleBounds: CGRect(origin: .zero, size: visibleSize).insetBy(dx: 10, dy: 10)
                    .offsetBy(dx: -canvasViewportOrigin.x, dy: -canvasViewportOrigin.y)
            ) { return }
        }
        hoveredID = eligible.first(where: { frames[$0].contains(point) }).map { entries[$0].id }
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
    var toolbarStyle: QuickAccessToolbarStyle
    var isHovering: Bool
    var viewportSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quickAccessDragOverlayEnabled) private var dragOverlayEnabled

    init(entry: QuickAccessEntry, placement: QuickAccessPlacement, thumbSize: NSSize,
         onClose: @escaping () -> Void, onAlternateAction: @escaping () -> Void,
         onDragSucceeded: (() -> Void)? = nil, onThumbnailClick: (() -> Void)? = nil,
         showsActionsOnHover: Bool = true, toolbarStyle: QuickAccessToolbarStyle = .below,
         isHovering: Bool = false, viewportSize: CGSize) {
        self.entry = entry
        self.placement = placement
        self.speculativeState = entry.speculativeState
        self.thumbSize = thumbSize
        self.onClose = onClose
        self.onAlternateAction = onAlternateAction
        self.onDragSucceeded = onDragSucceeded
        self.onThumbnailClick = onThumbnailClick
        self.showsActionsOnHover = showsActionsOnHover
        self.toolbarStyle = toolbarStyle
        self.isHovering = isHovering
        self.viewportSize = viewportSize
    }

    private var actions: [(symbol: String, label: String, action: () -> Void)] {
        [
            ("doc.on.clipboard", OctoshotL10n.quickAccessCopy, wrapDismissAfterSuccess(entry.actions.onCopy)),
            ("square.and.arrow.down", OctoshotL10n.quickAccessSave, wrapDismissAfterSuccess(entry.actions.onSave)),
            ("pencil.and.outline", OctoshotL10n.quickAccessAnnotate, wrapAlternate(entry.actions.onAnnotate)),
            ("pin", OctoshotL10n.quickAccessPin, wrapAlternate(entry.actions.onPin)),
            ("text.viewfinder", OctoshotL10n.ocrAction, wrapAlternate(entry.actions.onOCR)),
            ("xmark", OctoshotL10n.quickAccessDismissCapture, onClose)
        ]
    }

    var body: some View {
        QuickAccessThumbnailChrome(isHovering: showsActionsOnHover && isHovering, reduceMotion: reduceMotion) {
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbSize.width, height: thumbSize.height)
                .overlay {
                    if dragOverlayEnabled {
                        DraggableThumbnailView(image: entry.image, size: thumbSize,
                                               onClick: onThumbnailClick, onDragEnded: { operation in
                            if QuickAccessDragOutcome.fromEndedDragOperation(operation) == .removeFromStack {
                                onDragSucceeded?()
                            }
                        })
                        .frame(width: thumbSize.width, height: thumbSize.height)
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            if toolbarStyle == .below, showsActionsOnHover, isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white, Color.black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(OctoshotL10n.quickAccessDismissCapture)
                .accessibilityLabel(OctoshotL10n.quickAccessDismissCapture)
                .padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsActionsOnHover {
                toolbar
            }
        }
        .overlay(alignment: .top) {
            if isHovering {
                SpeculativePrimaryButton(phase: speculativeState.phase, onApply: applySpeculativeResult)
                    .offset(y: -40)
            }
        }
        .contextMenu {
            if let action = entry.actions.onAskAI {
                Button(OctoshotL10n.quickAccessAskAI, action: wrapAlternate(action))
            }
            if let action = entry.actions.onCopyMarkdown {
                Button(OctoshotL10n.quickAccessCopyMarkdown, action: wrapDismissAfterSuccess(action))
            }
            if let action = entry.actions.onCopyPath {
                Button(OctoshotL10n.quickAccessCopyPath, action: wrapDismissAfterSuccess(action))
            }
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if toolbarStyle == .below {
            let toolbarFrame = QuickAccessLayout.belowToolbarFrame(
                for: CGRect(origin: .zero, size: thumbSize), placement: placement
            )
            HStack(spacing: 6) {
                ForEach(actions.indices, id: \.self) { index in actionButton(index) }
            }
            .padding(5)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
            .fixedSize()
            .opacity(isHovering ? 1 : 0)
            .scaleEffect(isHovering ? 1 : 0.92)
            .position(x: toolbarFrame.midX, y: toolbarFrame.midY)
            .allowsHitTesting(isHovering)
            .accessibilityHidden(!isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
        } else {
            GeometryReader { proxy in
                let cardFrame = proxy.frame(in: .named("quickAccessViewport"))
                let bounds = CGRect(origin: .zero, size: viewportSize).insetBy(dx: 10, dy: 10)
                    .offsetBy(dx: -cardFrame.minX, dy: -cardFrame.minY)
                let geometry = QuickAccessRingGeometry(imageRect: CGRect(origin: .zero, size: thumbSize),
                                                       visibleBounds: bounds)
                QuickAccessRingPalette(diameter: geometry.outerBounds.width, actions: actions)
                    .frame(width: geometry.outerBounds.width, height: geometry.outerBounds.height)
                    .opacity(isHovering ? 1 : 0)
                    .scaleEffect(isHovering || reduceMotion ? 1 : 0.94)
                    .position(x: thumbSize.width / 2, y: thumbSize.height / 2)
                    .allowsHitTesting(isHovering)
                    .accessibilityHidden(!isHovering)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
            }
        }
    }

    private func actionButton(_ index: Int) -> some View {
        Button(action: actions[index].action) {
            Image(systemName: actions[index].symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: QuickAccessLayout.bubbleDiameter, height: QuickAccessLayout.bubbleDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(actions[index].label)
        .accessibilityLabel(actions[index].label)
    }

    private func wrapAlternate(_ action: @escaping () -> Void) -> () -> Void {
        {
            onAlternateAction()
            action()
        }
    }

    private func wrapDismissAfterSuccess(_ action: @escaping (@escaping () -> Void) -> Void) -> () -> Void {
        {
            onAlternateAction()
            action(onClose)
        }
    }

    private func applySpeculativeResult() {
        guard case .ready(_, let result) = speculativeState.phase else { return }
        switch result {
        case .latex(let text), .tableMarkdown(let text), .codeText(let text):
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else { return }
        case .redactedImage(let image):
            ImageExportActions.perform {
                try await ImageFormats.copyToPasteboardAsync(image)
                onAlternateAction()
                speculativeState.phase = .hidden
                onClose()
            }
            return
        }
        onAlternateAction()
        speculativeState.phase = .hidden
        onClose()
    }
}

private struct QuickAccessRingShape: Shape {
    var segment: Int?

    func path(in rect: CGRect) -> Path {
        let geometry = QuickAccessRingGeometry(imageRect: rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = segment.map { geometry.centerAngle(for: $0) - geometry.segmentAngle / 2 } ?? 0
        let end = start + (segment == nil ? 2 * .pi : geometry.segmentAngle)
        var path = Path()
        path.addArc(center: center, radius: geometry.outerRadius,
                    startAngle: .radians(Double(start)), endAngle: .radians(Double(end)), clockwise: false)
        let innerEnd = geometry.point(at: end, on: geometry.innerBounds)
        if segment != nil {
            path.addLine(to: innerEnd)
        } else {
            path.closeSubpath()
            path.move(to: innerEnd)
        }
        path.addArc(center: center, radius: geometry.innerRadius,
                    startAngle: .radians(Double(end)), endAngle: .radians(Double(start)), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct QuickAccessRingPalette: View {
    let diameter: CGFloat
    let actions: [(symbol: String, label: String, action: () -> Void)]
    @State private var highlightedSegment: Int?

    private var geometry: QuickAccessRingGeometry {
        QuickAccessRingGeometry(imageRect: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            QuickAccessRingShape()
                .fill(.ultraThinMaterial)
                .opacity(0.72)
                .overlay { QuickAccessRingShape().stroke(.white.opacity(0.42), lineWidth: 0.75) }
                .shadow(color: .black.opacity(0.24), radius: 7, y: 3)
            ForEach(actions.indices, id: \.self) { index in
                let shape = QuickAccessRingShape(segment: index)
                Button(action: actions[index].action) {
                    shape.fill(highlightedSegment == index ? Color.accentColor.opacity(0.32) : .clear)
                        .overlay(alignment: .topLeading) {
                            Image(systemName: actions[index].symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .position(geometry.center(for: index))
                        }
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .help(actions[index].label)
                .accessibilityLabel(actions[index].label)
                .accessibilityIdentifier("quick-access-ring-\(index)")
                Path { path in
                    let angle = geometry.centerAngle(for: index) - geometry.segmentAngle / 2
                    path.move(to: geometry.point(at: angle, on: geometry.innerBounds))
                    path.addLine(to: geometry.point(at: angle, on: geometry.outerBounds))
                }
                .stroke(.primary.opacity(0.16), lineWidth: 0.75)
                .allowsHitTesting(false)
            }
        }
        .contentShape(QuickAccessRingShape())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): highlightedSegment = geometry.segment(at: point)
            case .ended: highlightedSegment = nil
            }
        }
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
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
    var dragImage: NSImage? {
        didSet {
            guard dragImage !== oldValue else { return }
            prepareDragData()
        }
    }
    var onDragEnded: ((UInt) -> Void)?
    var onClick: (() -> Void)?

    private var mouseDownLocation: NSPoint?
    private var didBeginDrag = false
    private let dragThreshold: CGFloat = 5
    private var dragPayload: QuickAccessDragPayload?
    private var dragError: Error?
    private var preparationID = UUID()
    private var pendingDragEvent: NSEvent?

    private func prepareDragData() {
        let identifier = UUID()
        preparationID = identifier
        dragPayload = nil
        dragError = nil
        pendingDragEvent = nil
        guard let image = dragImage else { return }
        do {
            let snapshot = try ImageFormats.snapshot(image)
            Task { @MainActor [weak self] in
                do {
                    let payload = try await QuickAccessDragPayload.prepare(snapshot)
                    guard let self, self.preparationID == identifier else { return }
                    self.dragPayload = payload
                    self.startPreparedDrag()
                } catch {
                    guard let self, self.preparationID == identifier else { return }
                    self.dragError = error
                    if self.pendingDragEvent != nil {
                        self.pendingDragEvent = nil
                        self.mouseDownLocation = nil
                        NSAlert(error: error).runModal()
                    }
                }
            }
        } catch {
            dragError = error
        }
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {}

    override func mouseDown(with event: NSEvent) {
        if let dragPayload, Date().timeIntervalSince(dragPayload.preparedAt) >= QuickAccessDragPayload.maximumAge {
            prepareDragData()
        }
        pendingDragEvent = nil
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag, dragImage != nil, let start = mouseDownLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance >= dragThreshold else { return }
        if let dragError {
            mouseDownLocation = nil
            NSAlert(error: dragError).runModal()
            return
        }
        pendingDragEvent = event
        startPreparedDrag()
    }

    private func startPreparedDrag() {
        guard !didBeginDrag, let event = pendingDragEvent, let image = dragImage,
              let payload = dragPayload, mouseDownLocation != nil,
              NSEvent.pressedMouseButtons & 1 != 0 else { return }
        pendingDragEvent = nil
        didBeginDrag = true
        mouseDownLocation = nil

        let dragging = NSDraggingItem(pasteboardWriter: QuickAccessDragPasteboardWriter(payload: payload))
        dragging.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let wasPendingDrag = pendingDragEvent != nil
        pendingDragEvent = nil
        if !didBeginDrag, !wasPendingDrag, mouseDownLocation != nil {
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
        context == .outsideApplication ? [.copy, .generic] : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let droppedOnPanel = window?.frame.contains(screenPoint) == true
        onDragEnded?(droppedOnPanel ? 0 : operation.rawValue)
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
