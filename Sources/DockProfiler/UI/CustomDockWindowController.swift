import AppKit
import Combine
import SwiftUI

/// What the custom dock shows for a profile, derived so the panel only rebuilds
/// when something it draws has changed.
struct CustomDockContent: Equatable {
    var options = CustomDockOptions()
    var items: [DockStripItem] = []
    var others: [DockTile] = []
    /// The profile's colour, for a tinted slab.
    var color: ProfileColor = .blue
    /// The profile the dock belongs to, for a right-click to open its settings.
    var profileID: UUID?

    init(profile: DockProfile?) {
        guard let profile, profile.customDock.isActive else { return }
        options = profile.customDock
        color = profile.color
        profileID = profile.id
        switch options.mode {
        case .combined:
            items = profile.appRow
            others = profile.managesOthers ? profile.others : []
        case .detached:
            items = options.widgets.map { .widget($0) }
        }
    }

    var isActive: Bool { options.isActive && !(items.isEmpty && others.isEmpty) }
}

/// The dock inside its panel, with room around it for magnified tiles to grow into.
/// The panel is sized for the dock at rest; the grown dock overflows towards the
/// headroom, away from the edge and from the end it hugs.
private struct DockPanelContent: View {
    let dock: CustomDockView
    let placement: DockPlacement
    let magnificationExtra: CGFloat
    var openSettings: (() -> Void)? = nil

    var body: some View {
        let extra = magnificationExtra
        // Neighbours are pushed aside too, so the dock gets longer as well as taller.
        let along = extra * 3
        var insets = EdgeInsets()
        var alignment = Alignment.center
        switch placement.edge {
        case .bottom, .top:
            if placement.edge == .bottom { insets.top = extra + 4 } else { insets.bottom = extra + 4 }
            switch placement.alignment {
            case .leading: insets.trailing = along
            case .center: insets.leading = along / 2; insets.trailing = along / 2
            case .trailing: insets.leading = along
            }
            alignment = Alignment(
                horizontal: placement.alignment == .leading ? .leading : (placement.alignment == .trailing ? .trailing : .center),
                vertical: placement.edge == .bottom ? .bottom : .top
            )
        case .leading, .trailing:
            if placement.edge == .leading { insets.trailing = extra + 4 } else { insets.leading = extra + 4 }
            insets.top = along / 2
            insets.bottom = along / 2
            alignment = placement.edge == .leading ? .leading : .trailing
        }
        return dock
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(insets)
            .environment(\.dockSettingsAction, openSettings)
    }
}

/// A click on the dock should act at once, without the panel needing to be key.
private final class DockHostingView: NSHostingView<DockPanelContent> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The mark left on the edge while the dock is hidden: a sliver of the slab's own
/// material, the way a home indicator hints at what a swipe brings up. It keeps
/// quiet until the pointer heads its way, then comes forward a little.
private struct DockEdgeHint: View {
    let vertical: Bool
    let near: Bool
    var style: DockStyle = .system

    /// Glass draws a rim and shadow of its own, which is all there is room for in a
    /// sliver this thin; the plain material keeps the pill a clean line.
    private var material: DockStyle { style == .liquidGlass ? .system : style }

    var body: some View {
        Capsule(style: .continuous)
            .fill(DockPalette.onSlab.opacity(near ? 0.5 : 0.22))
            .background(DockMaterial(style: material, cornerRadius: DockEdgeHint.thickness / 2).id(material))
            .overlay(Capsule(style: .continuous).strokeBorder(DockPalette.rim, lineWidth: 0.5))
            .frame(
                width: vertical ? DockEdgeHint.thickness : nil,
                height: vertical ? nil : DockEdgeHint.thickness
            )
            .padding(DockEdgeHint.padding)
            .animation(.easeOut(duration: 0.2), value: near)
    }

    static let thickness: CGFloat = 4
    /// Room for the panel to draw a soft edge outside the pill.
    static let padding: CGFloat = 2
    /// How far in from the screen edge the pill sits.
    static let inset: CGFloat = 5
    /// How much of the dock's length the pill spans, within limits.
    static func length(along dockLength: CGFloat) -> CGFloat { min(max(dockLength * 0.35, 48), 160) }
}

/// Keeps the custom dock on screen for the active profile: a borderless panel on the
/// chosen edge of each display the profile asks for, none of which ever takes
/// focus. It follows the profile store, so editing the active profile updates the
/// dock as you go, and activating a profile without one takes it away. With
/// auto-hide on, each dock slides off its screen and comes back when the pointer
/// reaches its edge.
@MainActor
final class CustomDockWindowController {
    static let shared = CustomDockWindowController()

    /// One dock per display, in the order of `NSScreen.screens`.
    private var docks: [DockScreenPanel] = []
    private var content = CustomDockContent(profile: nil)
    private var cancellables = Set<AnyCancellable>()
    private var screenToken: NSObjectProtocol?
    private var spaceToken: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var backdropTimer: Timer?

    // Auto-hide
    private var pointerTimer: Timer?
    private var pointerTicks = 0
    private var missionControlUp = false

    var isVisible: Bool { docks.contains { $0.panel.isVisible } }

    /// The appearance the dock's style forces on its windows, when `window` is one
    /// of the dock's panels — the tooltip and stack panels take it too, so they
    /// match the slab they sit beside. Glass and no slab take theirs from the
    /// desktop under them, which can differ from one display to the next. Nil when
    /// the dock follows the system, or the window is not a dock.
    func forcedAppearance(in window: NSWindow) -> NSAppearance? {
        dock(for: window)?.forcedAppearance
    }

    /// Where the slab itself sits on screen when `window` is one of the dock's
    /// panels: the panel less the headroom on its far side that magnified tiles
    /// grow into. Nil for any other window, such as the editor showing a preview.
    func slabFrame(in window: NSWindow) -> NSRect? {
        dock(for: window)?.slabFrame
    }

    private func dock(for window: NSWindow) -> DockScreenPanel? {
        docks.first { $0.panel === window }
    }

    func start() {
        let store = ProfileStore.shared
        store.$profiles
            .combineLatest(store.$activeProfileID)
            .map { profiles, id in CustomDockContent(profile: profiles.first { $0.id == id }) }
            .removeDuplicates()
            .sink { [weak self] content in
                self?.apply(content)
            }
            .store(in: &cancellables)

        // The Dock comes back after activation with possibly a new size or edge, and
        // the panel sits relative to it.
        store.$lastActivatedAt
            .dropFirst()
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        RunningAppsMonitor.shared.$tiles
            .dropFirst()
            .sink { [weak self] _ in
                // The view lays out on the next pass; size the panels after it.
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)

        // A display plugged in or pulled out gets a dock or loses one; the rest move
        // with their screens.
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncDocks() }
        }

        // Each Space can have its own wallpaper, and a dynamic one changes with the
        // appearance; the dock's own appearance follows either.
        spaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAppearance() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.updateAppearance() }
        }
    }

    private func apply(_ content: CustomDockContent) {
        self.content = content
        DockStackController.shared.dismiss()
        syncDocks()
        if content.isActive, content.options.autohide {
            startPointerTracking()
        } else {
            stopPointerTracking()
        }
        watchBackdropIfNeeded()
    }

    /// One dock per display the profile asks for, keeping those already on screen
    /// so a change to the profile does not make every dock start over.
    private func syncDocks() {
        guard content.isActive else {
            docks.forEach { $0.remove() }
            docks = []
            return
        }
        var kept: [DockScreenPanel] = []
        for screen in content.options.screens {
            let key = screen.displayKey
            let dock = docks.first { $0.key == key } ?? DockScreenPanel(key: key, screen: screen)
            dock.apply(content, on: screen, missionControlUp: missionControlUp)
            kept.append(dock)
        }
        for dock in docks where !kept.contains(where: { $0 === dock }) {
            dock.remove()
        }
        docks = kept
    }

    func reposition() {
        for dock in docks { dock.reposition() }
    }

    // MARK: - Appearance

    private func updateAppearance() {
        for dock in docks { dock.updateAppearance() }
    }

    /// For a style that shows the desktop through, the wallpaper under each slab is
    /// read again on a slow tick, since a new wallpaper announces itself no other way.
    private func watchBackdropIfNeeded() {
        let style = content.options.look.style
        let watching = content.isActive && style.showsDesktop && style.forcedAppearance == nil
        if watching, backdropTimer == nil {
            backdropTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAppearance() }
            }
        } else if !watching {
            backdropTimer?.invalidate()
            backdropTimer = nil
        }
    }

    /// Writes an order dragged together in the dock back to the active profile: the
    /// app row when the dock is combined, the widgets alone when it is detached.
    fileprivate static func reorder(_ row: [DockStripItem]) {
        let store = ProfileStore.shared
        guard var profile = store.activeProfile else { return }
        if profile.customDock.mode == .combined {
            profile.setAppRow(row)
        } else {
            profile.customDock.widgets = row.compactMap(\.widget)
        }
        store.update(profile)
    }

    /// A right-click on the dock: the Custom Dock tab of the profile showing it.
    fileprivate static func openSettings(of profileID: UUID) {
        ManagerWindowController.shared.showCustomDock(of: profileID)
    }

    // MARK: - Levels

    /// Just above the macOS Dock's own level. Mission Control hides ordinary floating
    /// windows but leaves the Dock's level on screen, so a combined dock drawn here
    /// shows up in Mission Control — in front of the parked Dock, which Mission
    /// Control insists on drawing regardless.
    static let standInLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    /// For the tooltip and stack panels, so they sit over the dock in either mode.
    static let accessoryLevel = NSWindow.Level(rawValue: standInLevel.rawValue + 1)

    // MARK: - Auto-hide

    /// Watching the pointer needs no permission: its position is public, and the
    /// docks only care whether it has come to their edge.
    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    private func trackPointer() {
        // Mission Control shows an auto-hidden Dock; show ours too, for as long as it is up.
        pointerTicks &+= 1
        if pointerTicks % 3 == 0 { missionControlUp = Self.isMissionControlUp() }
        let mouse = NSEvent.mouseLocation
        for dock in docks {
            dock.trackPointer(at: mouse, missionControlUp: missionControlUp)
        }
    }

    /// Whether Mission Control is up. Nothing announces it, but while it is, the Dock
    /// process owns a screen-sized window at level 18 that exists at no other time.
    private static func isMissionControlUp() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                  window[kCGWindowLayer as String] as? Int == 18,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return width >= 1000 && height >= 600
        }
    }
}

// MARK: - One display's dock

/// The dock on one display: its panel, the mark it leaves on the edge while
/// hidden, and whether it is on show. The controller keeps one per display the
/// profile asks for, each on the edge that display was given.
@MainActor
private final class DockScreenPanel {
    /// `NSScreen.displayKey`, so the dock finds its display again after the screens
    /// are re-listed.
    let key: String
    private(set) var screen: NSScreen
    private var content = CustomDockContent(profile: nil)
    private var placement = DockPlacement()
    private var options: CustomDockOptions { content.options }
    private var edge: DockStripEdge { placement.edge }

    let panel: NSPanel
    private let hosting: DockHostingView
    private var hintPanel: NSPanel?
    private var hintHosting: NSHostingView<DockEdgeHint>?
    private var hintShown = false
    private var pointerNearHint = false
    private var revealed = true
    private var hideTask: Task<Void, Never>?
    private var missionControlUp = false
    /// For a style that shows the desktop through: light or dark to suit the
    /// wallpaper under the slab. Nil when the style has its own, or the desktop
    /// could not be read. See `DesktopBackdrop`.
    private var desktopAppearance: NSAppearance?

    init(key: String, screen: NSScreen) {
        self.key = key
        self.screen = screen

        let hosting = DockHostingView(rootView: DockPanelContent(
            dock: CustomDockView(items: []), placement: DockPlacement(), magnificationExtra: 0
        ))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        self.hosting = hosting
        self.panel = panel
    }

    /// The appearance the dock's style forces on its windows: the style's own, or
    /// for glass and no slab, the one that reads against the wallpaper under it.
    var forcedAppearance: NSAppearance? {
        options.look.style.forcedAppearance ?? desktopAppearance
    }

    /// The panel less the headroom on its far side that magnified tiles grow into.
    var slabFrame: NSRect { slabFrame(in: panel.frame) }

    private func slabFrame(in panelFrame: NSRect) -> NSRect {
        var frame = panelFrame
        let headroom = options.magnificationExtra + 4
        switch edge {
        case .bottom: frame.size.height -= headroom
        case .top: frame.origin.y += headroom; frame.size.height -= headroom
        case .leading: frame.size.width -= headroom
        case .trailing: frame.origin.x += headroom; frame.size.width -= headroom
        }
        return frame
    }

    func apply(_ content: CustomDockContent, on screen: NSScreen, missionControlUp: Bool) {
        self.content = content
        self.screen = screen
        self.missionControlUp = missionControlUp
        placement = content.options.placement(for: screen)

        // Standing in for the Dock, the panel takes the Dock's place in Mission Control
        // too. Beside a live Dock it stays below, so an auto-hidden Dock still slides
        // in over it.
        panel.level = options.mode == .combined ? CustomDockWindowController.standInLevel : .floating
        hintPanel?.level = panel.level
        hosting.rootView = DockPanelContent(
            dock: CustomDockView(
                items: content.items,
                others: content.others,
                showsRunningApps: options.mode == .combined && options.showsRunningApps,
                edge: edge,
                tileSize: options.tileSize,
                magnificationExtra: options.magnificationExtra,
                look: options.look,
                tint: content.color.color,
                onReorder: CustomDockWindowController.reorder
            ),
            placement: placement,
            magnificationExtra: options.magnificationExtra,
            openSettings: content.profileID.map { id in { CustomDockWindowController.openSettings(of: id) } }
        )

        if options.autohide {
            if revealed {
                reposition()
                panel.orderFrontRegardless()
            }
        } else {
            hideTask?.cancel()
            hideTask = nil
            revealed = true
            panel.alphaValue = 1
            reposition()
            panel.orderFrontRegardless()
        }
        updateAppearance()
        updateHint()
    }

    /// Takes the dock off its display: the profile no longer wants one there, or
    /// the display has gone.
    func remove() {
        hideTask?.cancel()
        hideTask = nil
        panel.orderOut(nil)
        hintPanel?.orderOut(nil)
        hintShown = false
    }

    // MARK: - Appearance

    /// Sets the panels' appearance: the style's own, or for glass and no slab, one
    /// that reads against the wallpaper under the slab. Read again whenever the
    /// dock moves or the desktop might have changed.
    func updateAppearance(shown: NSRect? = nil) {
        let style = options.look.style
        var fromDesktop: NSAppearance?
        if style.forcedAppearance == nil, style.showsDesktop,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
           let shown = shown ?? shownFrame(),
           let light = DesktopBackdrop.shared.isLight(under: slabFrame(in: shown), on: screen) {
            fromDesktop = NSAppearance(named: light ? .aqua : .darkAqua)
        }
        desktopAppearance = fromDesktop

        let appearance = forcedAppearance
        if panel.appearance?.name != appearance?.name {
            panel.appearance = appearance
            hintPanel?.appearance = appearance
        }
    }

    // MARK: - Frames

    /// Where the dock sits when it is on show: snug against its edge, on the side
    /// the profile asked for. `visibleFrame` already leaves out the macOS Dock.
    private func shownFrame() -> NSRect? {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }

        let visible = screen.visibleFrame
        let margin: CGFloat = 8
        var origin = NSPoint.zero

        switch edge {
        case .bottom, .top:
            switch placement.alignment {
            case .leading: origin.x = visible.minX + margin
            case .center: origin.x = visible.midX - size.width / 2
            case .trailing: origin.x = visible.maxX - size.width - margin
            }
            origin.y = edge == .bottom ? visible.minY + margin : visible.maxY - size.height - margin
        case .leading, .trailing:
            origin.x = edge == .leading ? visible.minX + margin : visible.maxX - size.width - margin
            origin.y = visible.midY - size.height / 2
        }
        return NSRect(origin: origin, size: size)
    }

    /// The same frame pushed just past its edge, out of sight.
    private func hiddenFrame(from shown: NSRect) -> NSRect {
        let visible = screen.visibleFrame
        var frame = shown
        switch edge {
        case .bottom: frame.origin.y = visible.minY - shown.height - 12
        case .top: frame.origin.y = visible.maxY + 12
        case .leading: frame.origin.x = visible.minX - shown.width - 12
        case .trailing: frame.origin.x = visible.maxX + 12
        }
        return frame
    }

    func reposition() {
        guard let shown = shownFrame() else { return }
        panel.setFrame(revealed ? shown : hiddenFrame(from: shown), display: true)
        if let hintPanel, hintShown {
            hintPanel.setFrame(hintFrame(for: shown), display: true)
        }
        // A different spot on the desktop may want a different appearance.
        if options.look.style.showsDesktop {
            updateAppearance(shown: shown)
        }
    }

    // MARK: - Auto-hide

    func trackPointer(at mouse: NSPoint, missionControlUp: Bool) {
        self.missionControlUp = missionControlUp
        guard options.autohide, let shown = shownFrame() else { return }

        if missionControlUp {
            hideTask?.cancel()
            hideTask = nil
            if !revealed { reveal() }
            return
        }
        if !revealed { setPointerNearHint(approachZone(for: shown).contains(mouse)) }

        if revealed {
            // Leave a little room around the dock before it slips away again — and
            // stay while a stack is open from it, since the pointer is up in that panel.
            let stackOpen = DockStackController.shared.isOpen && screen.frame.contains(mouse)
            if shown.insetBy(dx: -24, dy: -24).contains(mouse) || stackOpen {
                hideTask?.cancel()
                hideTask = nil
            } else if hideTask == nil {
                hideTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    self.hideTask = nil
                    self.hide()
                }
            }
        } else if triggerZone(for: shown).contains(mouse) {
            reveal()
        }
    }

    /// A thin band along the edge, as wide as the dock plus a little, that the
    /// pointer runs into on its way to where the dock would be.
    private func triggerZone(for shown: NSRect) -> NSRect {
        let visible = screen.visibleFrame
        let reach: CGFloat = 40
        let depth: CGFloat = 6
        switch edge {
        case .bottom:
            return NSRect(x: shown.minX - reach, y: visible.minY, width: shown.width + reach * 2, height: depth)
        case .top:
            return NSRect(x: shown.minX - reach, y: visible.maxY - depth, width: shown.width + reach * 2, height: depth)
        case .leading:
            return NSRect(x: visible.minX, y: shown.minY - reach, width: depth, height: shown.height + reach * 2)
        case .trailing:
            return NSRect(x: visible.maxX - depth, y: shown.minY - reach, width: depth, height: shown.height + reach * 2)
        }
    }

    /// The band the pointer crosses on its way to the trigger zone: the same span,
    /// but deep enough to see it coming. The edge mark brightens while it is here.
    private func approachZone(for shown: NSRect) -> NSRect {
        let zone = triggerZone(for: shown)
        return edge.isVertical
            ? zone.insetBy(dx: -40, dy: 0)
            : zone.insetBy(dx: 0, dy: -40)
    }

    private func reveal() {
        guard !revealed, let shown = shownFrame() else { return }
        revealed = true
        hideHint()
        panel.setFrame(hiddenFrame(from: shown), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(shown, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard revealed, let shown = shownFrame() else { return }
        revealed = false
        DockTooltipController.shared.cancel()
        DockStackController.shared.dismiss()
        let panel = panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(self.hiddenFrame(from: shown), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard !self.revealed else { return }
                panel.orderOut(nil)
                self.updateHint()
            }
        })
    }

    // MARK: - Edge hint

    private var wantsHint: Bool {
        options.autohide && options.edgeHint && !revealed && !missionControlUp
    }

    private func updateHint() {
        if wantsHint { showHint() } else { hideHint() }
    }

    private func makeHintPanelIfNeeded() {
        guard hintPanel == nil else { return }
        let hosting = NSHostingView(rootView: DockEdgeHint(vertical: false, near: false))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = self.panel.level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = forcedAppearance
        // The pointer passes straight through to the trigger zone underneath.
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        hintPanel = panel
        hintHosting = hosting
    }

    /// The pill's panel: centred on the slab along the edge, a few points in from it.
    private func hintFrame(for shown: NSRect) -> NSRect {
        let visible = screen.visibleFrame
        let padding = DockEdgeHint.padding
        let thickness = DockEdgeHint.thickness + padding * 2
        let inset = DockEdgeHint.inset - padding
        // The panel carries headroom along the edge for magnified tiles; the slab
        // is what is left, hugging the end the profile asked for.
        let along = options.magnificationExtra * 3

        switch edge {
        case .bottom, .top:
            let slabWidth = shown.width - along
            let slabMidX: CGFloat
            switch placement.alignment {
            case .leading: slabMidX = shown.minX + slabWidth / 2
            case .center: slabMidX = shown.midX
            case .trailing: slabMidX = shown.maxX - slabWidth / 2
            }
            let length = DockEdgeHint.length(along: slabWidth) + padding * 2
            let y = edge == .bottom ? visible.minY + inset : visible.maxY - inset - thickness
            return NSRect(x: slabMidX - length / 2, y: y, width: length, height: thickness)
        case .leading, .trailing:
            let slabHeight = shown.height - along
            let length = DockEdgeHint.length(along: slabHeight) + padding * 2
            let x = edge == .leading ? visible.minX + inset : visible.maxX - inset - thickness
            return NSRect(x: x, y: shown.midY - length / 2, width: thickness, height: length)
        }
    }

    private func showHint() {
        guard let shown = shownFrame() else { return }
        makeHintPanelIfNeeded()
        guard let hintPanel, let hintHosting else { return }
        hintHosting.rootView = DockEdgeHint(vertical: edge.isVertical, near: pointerNearHint, style: options.look.style)
        hintPanel.setFrame(hintFrame(for: shown), display: true)
        guard !hintShown else { return }
        hintShown = true
        hintPanel.alphaValue = 0
        hintPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hintPanel.animator().alphaValue = 1
        }
    }

    private func hideHint() {
        guard hintShown, let hintPanel else { return }
        hintShown = false
        pointerNearHint = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hintPanel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if !self.hintShown { hintPanel.orderOut(nil) }
            }
        })
    }

    private func setPointerNearHint(_ near: Bool) {
        guard near != pointerNearHint else { return }
        pointerNearHint = near
        guard hintShown, let hintHosting else { return }
        hintHosting.rootView = DockEdgeHint(vertical: edge.isVertical, near: near, style: options.look.style)
    }
}
