import AppKit
import Combine
import SwiftUI

/// What the custom dock shows for a profile, derived so the panel only rebuilds
/// when something it draws has changed.
struct CustomDockContent: Equatable {
    var options = CustomDockOptions()
    var items: [DockStripItem] = []
    var others: [DockTile] = []

    init(profile: DockProfile?) {
        guard let profile, profile.customDock.isActive else { return }
        options = profile.customDock
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
    let options: CustomDockOptions

    var body: some View {
        let extra = options.magnificationExtra
        // Neighbours are pushed aside too, so the dock gets longer as well as taller.
        let along = extra * 3
        var insets = EdgeInsets()
        var alignment = Alignment.center
        switch options.edge {
        case .bottom, .top:
            if options.edge == .bottom { insets.top = extra + 4 } else { insets.bottom = extra + 4 }
            switch options.alignment {
            case .leading: insets.trailing = along
            case .center: insets.leading = along / 2; insets.trailing = along / 2
            case .trailing: insets.leading = along
            }
            alignment = Alignment(
                horizontal: options.alignment == .leading ? .leading : (options.alignment == .trailing ? .trailing : .center),
                vertical: options.edge == .bottom ? .bottom : .top
            )
        case .leading, .trailing:
            if options.edge == .leading { insets.trailing = extra + 4 } else { insets.leading = extra + 4 }
            insets.top = along / 2
            insets.bottom = along / 2
            alignment = options.edge == .leading ? .leading : .trailing
        }
        return dock
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(insets)
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

    var body: some View {
        Capsule(style: .continuous)
            .fill(DockPalette.onSlab.opacity(near ? 0.5 : 0.22))
            .background(DockMaterial(cornerRadius: DockEdgeHint.thickness / 2))
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
/// chosen edge that never takes focus. It follows the profile store, so editing the
/// active profile updates the dock as you go, and activating a profile without one
/// takes it away. With auto-hide on, the dock slides off screen and comes back when
/// the pointer reaches its edge.
@MainActor
final class CustomDockWindowController {
    static let shared = CustomDockWindowController()

    private var panel: NSPanel?
    private var hosting: DockHostingView?
    private var hintPanel: NSPanel?
    private var hintHosting: NSHostingView<DockEdgeHint>?
    private var hintShown = false
    private var pointerNearHint = false
    private var content = CustomDockContent(profile: nil)
    private var cancellables = Set<AnyCancellable>()
    private var screenToken: NSObjectProtocol?

    // Auto-hide
    private var pointerTimer: Timer?
    private var revealed = true
    private var hideTask: Task<Void, Never>?
    private var pointerTicks = 0
    private var missionControlUp = false

    var isVisible: Bool { panel?.isVisible == true }

    /// Where the slab itself sits on screen when `window` is the dock's panel: the
    /// panel less the headroom on its far side that magnified tiles grow into. Nil
    /// for any other window, such as the editor showing a preview.
    func slabFrame(in window: NSWindow) -> NSRect? {
        guard let panel, window === panel else { return nil }
        var frame = panel.frame
        let headroom = content.options.magnificationExtra + 4
        switch content.options.edge {
        case .bottom: frame.size.height -= headroom
        case .top: frame.origin.y += headroom; frame.size.height -= headroom
        case .leading: frame.size.width -= headroom
        case .trailing: frame.origin.x += headroom; frame.size.width -= headroom
        }
        return frame
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

        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    private func apply(_ content: CustomDockContent) {
        self.content = content
        DockStackController.shared.dismiss()
        guard content.isActive else {
            stopPointerTracking()
            panel?.orderOut(nil)
            hideHint()
            return
        }
        makePanelIfNeeded()
        // Standing in for the Dock, the panel takes the Dock's place in Mission Control
        // too. Beside a live Dock it stays below, so an auto-hidden Dock still slides
        // in over it.
        panel?.level = content.options.mode == .combined ? Self.standInLevel : .floating
        hintPanel?.level = panel?.level ?? .floating
        hosting?.rootView = DockPanelContent(
            dock: CustomDockView(
                items: content.items,
                others: content.others,
                showsRunningApps: content.options.mode == .combined && content.options.showsRunningApps,
                edge: content.options.edge,
                tileSize: content.options.tileSize,
                magnificationExtra: content.options.magnificationExtra,
                onReorder: Self.reorder
            ),
            options: content.options
        )

        if content.options.autohide {
            startPointerTracking()
            if revealed {
                reposition()
                panel?.orderFrontRegardless()
            }
        } else {
            stopPointerTracking()
            revealed = true
            panel?.alphaValue = 1
            reposition()
            panel?.orderFrontRegardless()
        }
        updateHint()
    }

    /// Writes an order dragged together in the dock back to the active profile: the
    /// app row when the dock is combined, the widgets alone when it is detached.
    private static func reorder(_ row: [DockStripItem]) {
        let store = ProfileStore.shared
        guard var profile = store.activeProfile else { return }
        if profile.customDock.mode == .combined {
            profile.setAppRow(row)
        } else {
            profile.customDock.widgets = row.compactMap(\.widget)
        }
        store.update(profile)
    }

    // MARK: - Panel

    /// Just above the macOS Dock's own level. Mission Control hides ordinary floating
    /// windows but leaves the Dock's level on screen, so a combined dock drawn here
    /// shows up in Mission Control — in front of the parked Dock, which Mission
    /// Control insists on drawing regardless.
    static let standInLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    /// For the tooltip and stack panels, so they sit over the dock in either mode.
    static let accessoryLevel = NSWindow.Level(rawValue: standInLevel.rawValue + 1)

    private func makePanelIfNeeded() {
        guard panel == nil else { return }

        let hosting = DockHostingView(rootView: DockPanelContent(dock: CustomDockView(items: []), options: CustomDockOptions()))
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
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        self.hosting = hosting
        self.panel = panel

        RunningAppsMonitor.shared.$tiles
            .dropFirst()
            .sink { [weak self] _ in
                // The view lays out on the next pass; size the panel after it.
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)
    }

    /// The Dock lives on the primary display, which is always first in the list.
    private var screen: NSScreen? { NSScreen.screens.first }

    /// Where the dock sits when it is on show: snug against its edge, on the side
    /// the profile asked for. `visibleFrame` already leaves out the macOS Dock.
    private func shownFrame() -> NSRect? {
        guard let hosting, let screen else { return nil }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }

        let visible = screen.visibleFrame
        let margin: CGFloat = 8
        let options = content.options
        var origin = NSPoint.zero

        switch options.edge {
        case .bottom, .top:
            switch options.alignment {
            case .leading: origin.x = visible.minX + margin
            case .center: origin.x = visible.midX - size.width / 2
            case .trailing: origin.x = visible.maxX - size.width - margin
            }
            origin.y = options.edge == .bottom ? visible.minY + margin : visible.maxY - size.height - margin
        case .leading, .trailing:
            origin.x = options.edge == .leading ? visible.minX + margin : visible.maxX - size.width - margin
            origin.y = visible.midY - size.height / 2
        }
        return NSRect(origin: origin, size: size)
    }

    /// The same frame pushed just past its edge, out of sight.
    private func hiddenFrame(from shown: NSRect) -> NSRect {
        guard let screen else { return shown }
        let visible = screen.visibleFrame
        var frame = shown
        switch content.options.edge {
        case .bottom: frame.origin.y = visible.minY - shown.height - 12
        case .top: frame.origin.y = visible.maxY + 12
        case .leading: frame.origin.x = visible.minX - shown.width - 12
        case .trailing: frame.origin.x = visible.maxX + 12
        }
        return frame
    }

    func reposition() {
        guard let panel, content.isActive, let shown = shownFrame() else { return }
        panel.setFrame(revealed ? shown : hiddenFrame(from: shown), display: true)
        if let hintPanel, hintShown {
            hintPanel.setFrame(hintFrame(for: shown), display: true)
        }
    }

    // MARK: - Auto-hide

    /// Watching the pointer needs no permission: its position is public, and the
    /// dock only cares whether it has come to the edge.
    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        hideTask?.cancel()
        hideTask = nil
    }

    private func trackPointer() {
        guard let shown = shownFrame() else { return }
        let mouse = NSEvent.mouseLocation

        // Mission Control shows an auto-hidden Dock; show ours too, for as long as it is up.
        pointerTicks &+= 1
        if pointerTicks % 3 == 0 { missionControlUp = Self.isMissionControlUp() }
        if missionControlUp {
            hideTask?.cancel()
            hideTask = nil
            if !revealed { reveal() }
            return
        }
        if !revealed { setPointerNearHint(approachZone(for: shown).contains(mouse)) }

        if revealed {
            // Leave a little room around the dock before it slips away again — and
            // stay while a stack is open, since the pointer is up in that panel.
            if shown.insetBy(dx: -24, dy: -24).contains(mouse) || DockStackController.shared.isOpen {
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

    /// A thin band along the edge, as wide as the dock plus a little, that the
    /// pointer runs into on its way to where the dock would be.
    private func triggerZone(for shown: NSRect) -> NSRect {
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        let reach: CGFloat = 40
        let depth: CGFloat = 6
        switch content.options.edge {
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
        return content.options.edge.isVertical
            ? zone.insetBy(dx: -40, dy: 0)
            : zone.insetBy(dx: 0, dy: -40)
    }

    private func reveal() {
        guard let panel, !revealed, let shown = shownFrame() else { return }
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
        guard let panel, revealed, let shown = shownFrame() else { return }
        revealed = false
        DockTooltipController.shared.cancel()
        DockStackController.shared.dismiss()
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
        content.isActive && content.options.autohide && content.options.edgeHint && !revealed && !missionControlUp
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
        panel.level = self.panel?.level ?? .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // The pointer passes straight through to the trigger zone underneath.
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        hintPanel = panel
        hintHosting = hosting
    }

    /// The pill's panel: centred on the slab along the edge, a few points in from it.
    private func hintFrame(for shown: NSRect) -> NSRect {
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        let options = content.options
        let padding = DockEdgeHint.padding
        let thickness = DockEdgeHint.thickness + padding * 2
        let inset = DockEdgeHint.inset - padding
        // The panel carries headroom along the edge for magnified tiles; the slab
        // is what is left, hugging the end the profile asked for.
        let along = options.magnificationExtra * 3

        switch options.edge {
        case .bottom, .top:
            let slabWidth = shown.width - along
            let slabMidX: CGFloat
            switch options.alignment {
            case .leading: slabMidX = shown.minX + slabWidth / 2
            case .center: slabMidX = shown.midX
            case .trailing: slabMidX = shown.maxX - slabWidth / 2
            }
            let length = DockEdgeHint.length(along: slabWidth) + padding * 2
            let y = options.edge == .bottom ? visible.minY + inset : visible.maxY - inset - thickness
            return NSRect(x: slabMidX - length / 2, y: y, width: length, height: thickness)
        case .leading, .trailing:
            let slabHeight = shown.height - along
            let length = DockEdgeHint.length(along: slabHeight) + padding * 2
            let x = options.edge == .leading ? visible.minX + inset : visible.maxX - inset - thickness
            return NSRect(x: x, y: shown.midY - length / 2, width: thickness, height: length)
        }
    }

    private func showHint() {
        guard let shown = shownFrame() else { return }
        makeHintPanelIfNeeded()
        guard let hintPanel, let hintHosting else { return }
        hintHosting.rootView = DockEdgeHint(vertical: content.options.edge.isVertical, near: pointerNearHint)
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
        hintHosting.rootView = DockEdgeHint(vertical: content.options.edge.isVertical, near: near)
    }
}
