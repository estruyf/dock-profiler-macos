import AppKit
import SwiftUI

// MARK: - Environment

/// The height of an app icon or widget card, and whether the dock is a column.
/// Set once on the dock; every tile and widget draws itself to fit.
private struct DockTileSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 56
}

/// How far a tile sits inside the slab's edge: the slab's padding. A tile's menu
/// opens clear of the slab, not of the tile, so it needs to know.
private struct DockSlabInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct DockVerticalKey: EnvironmentKey {
    static let defaultValue = false
}

/// Whether app tiles carry the Dock's notification badges.
private struct DockBadgesKey: EnvironmentKey {
    static let defaultValue = false
}

/// Whether widgets draw a card behind themselves.
private struct DockTileCardsKey: EnvironmentKey {
    static let defaultValue = true
}

/// Opens the dock's settings, from a right-click on the live dock. Nil in the
/// editor's preview, which is already in the settings.
private struct DockSettingsActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// Takes the tile or widget out of the profile, from its context menu. Set on
/// each item that can go; nil on a running app that is not pinned.
private struct DockRemoveActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// Puts a running app that is not in the profile into it, from its context
/// menu — the Dock's Keep in Dock. Set on the live dock's running section only.
private struct DockPinActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

/// The widget a context menu belongs to, so its settings can sit in the menu.
private struct DockWidgetKey: EnvironmentKey {
    static let defaultValue: WidgetTile? = nil
}

/// Writes a widget's changed settings back to the profile. Set on the live dock;
/// nil in the editor's preview, whose cards have the settings already.
private struct DockWidgetUpdateKey: EnvironmentKey {
    static let defaultValue: ((WidgetTile) -> Void)? = nil
}

extension EnvironmentValues {
    var dockTileSize: CGFloat {
        get { self[DockTileSizeKey.self] }
        set { self[DockTileSizeKey.self] = newValue }
    }

    var dockSlabInset: CGFloat {
        get { self[DockSlabInsetKey.self] }
        set { self[DockSlabInsetKey.self] = newValue }
    }

    var dockVertical: Bool {
        get { self[DockVerticalKey.self] }
        set { self[DockVerticalKey.self] = newValue }
    }

    var dockShowsBadges: Bool {
        get { self[DockBadgesKey.self] }
        set { self[DockBadgesKey.self] = newValue }
    }

    var dockTileCards: Bool {
        get { self[DockTileCardsKey.self] }
        set { self[DockTileCardsKey.self] = newValue }
    }

    var dockSettingsAction: (() -> Void)? {
        get { self[DockSettingsActionKey.self] }
        set { self[DockSettingsActionKey.self] = newValue }
    }

    var dockRemoveAction: (() -> Void)? {
        get { self[DockRemoveActionKey.self] }
        set { self[DockRemoveActionKey.self] = newValue }
    }

    var dockPinAction: (() -> Void)? {
        get { self[DockPinActionKey.self] }
        set { self[DockPinActionKey.self] = newValue }
    }

    var dockWidget: WidgetTile? {
        get { self[DockWidgetKey.self] }
        set { self[DockWidgetKey.self] = newValue }
    }

    var dockWidgetUpdate: ((WidgetTile) -> Void)? {
        get { self[DockWidgetUpdateKey.self] }
        set { self[DockWidgetUpdateKey.self] = newValue }
    }

    /// Opens the Widgets tab of the profile's editor; nil in the editor's preview.
    var dockWidgetsAction: (() -> Void)? {
        get { self[DockWidgetsActionKey.self] }
        set { self[DockWidgetsActionKey.self] = newValue }
    }

    /// Takes an entry out of the stack with the id, to stand on its own beside it.
    var dockStackMoveOut: ((AppStackEntry, UUID) -> Void)? {
        get { self[DockStackMoveOutKey.self] }
        set { self[DockStackMoveOutKey.self] = newValue }
    }

    /// Folds the tile into an app stack, from its context menu; nil where it cannot be stacked.
    var dockStacking: DockStacking? {
        get { self[DockStackingKey.self] }
        set { self[DockStackingKey.self] = newValue }
    }

    /// A held tile is over this stack: letting go folds it in.
    var dockStackTargeted: Bool {
        get { self[DockStackTargetedKey.self] }
        set { self[DockStackTargetedKey.self] = newValue }
    }

    /// The dock's length has changed by its own doing — capped, or the cap
    /// dragged — so the panel around it needs fitting again. Nil in the editor's
    /// preview, which lays out with its window.
    var dockLayoutChanged: (() -> Void)? {
        get { self[DockLayoutChangedKey.self] }
        set { self[DockLayoutChangedKey.self] = newValue }
    }
}

private struct DockLayoutChangedKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct DockStackTargetedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DockWidgetsActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct DockStackMoveOutKey: EnvironmentKey {
    static let defaultValue: ((AppStackEntry, UUID) -> Void)? = nil
}

/// Folds a tile into an app stack from its context menu — the same as dragging
/// it onto one: into a stack already in the row, or into a new stack made in
/// the tile's place. Set on each app tile and launcher the row can rearrange.
struct DockStacking {
    /// The app stacks in the row the tile could join, in their order.
    var stacks: [WidgetTile]
    /// Folds the tile into the stack with the id, or with nil into a new one.
    var add: (UUID?) -> Void
}

private struct DockStackingKey: EnvironmentKey {
    static let defaultValue: DockStacking? = nil
}

private extension WidgetTile {
    /// App stack: the name it goes by in a menu listing several — its first few
    /// apps, since every stack shares the kind's title.
    var stackMenuTitle: String {
        let names = stack.prefix(3).map(\.title)
        guard !names.isEmpty else { return "Empty Stack" }
        return names.joined(separator: ", ") + (stack.count > names.count ? "…" : "")
    }
}

// MARK: - Context menus

/// A tile's context menu in the dock: Remove from Dock for one that is in the
/// profile and, on the live dock, a way to the dock's settings, first, so they
/// are found at once; then, under a divider, the tile's own items and, for a
/// widget with settings, those, right there in the menu. A tile with nothing of
/// its own still gets the first two, so a right-click anywhere on the dock finds
/// them.
private struct DockContextMenu<Items: View>: ViewModifier {
    let items: Items

    @Environment(\.dockSettingsAction) private var openSettings
    @Environment(\.dockWidgetsAction) private var openWidgets
    @Environment(\.dockRemoveAction) private var remove
    @Environment(\.dockStacking) private var stacking
    @Environment(\.dockWidget) private var widget
    @Environment(\.dockWidgetUpdate) private var update
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockSlabInset) private var slabInset

    private var hasSettings: Bool { widget?.kind.isConfigurable == true && update != nil }

    func body(content: Content) -> some View {
        if #available(macOS 14.4, *) {
            content.overlay(DockMenuAnchor(edge: edge, inset: slabInset) {
                DockTooltipController.shared.cancel()
                return NSHostingMenu(rootView: menu)
            })
        } else {
            // Before `NSHostingMenu`, SwiftUI's own menu, which opens at the pointer.
            content.contextMenu { menu }
        }
    }

    /// The items as SwiftUI has them; `NSHostingMenu` turns them into the menu.
    private var menu: some View {
        Group {
            if let remove { Button("Remove from Dock", action: remove) }
            if let stacking { DockStackingMenu(stacking: stacking) }
            // A widget's menu leads to the Widgets tab, where its card is.
            if let openWidgets { Button("Widget Settings…", action: openWidgets) }
            else if let openSettings { Button("Custom Dock Settings…", action: openSettings) }
            if remove != nil || stacking != nil || openSettings != nil, hasSettings || Items.self != EmptyView.self { Divider() }
            items
            if hasSettings, Items.self != EmptyView.self { Divider() }
            if hasSettings, let widget, let update {
                WidgetSettingsMenu(tile: widget, update: update)
            }
        }
    }
}

/// Add to Stack: the stacks already in the row, then a new one. As menu items
/// for `DockContextMenu`; `DockStacking.menuItem` is the same for an `NSMenu`.
private struct DockStackingMenu: View {
    let stacking: DockStacking

    var body: some View {
        Menu("Add to Stack") {
            ForEach(stacking.stacks) { stack in
                Button(stack.stackMenuTitle) { stacking.add(stack.id) }
            }
            if !stacking.stacks.isEmpty { Divider() }
            Button("New Stack") { stacking.add(nil) }
        }
    }
}

/// A widget's settings as menu items — the same ones its card in the editor has,
/// so the dock can be set up without leaving it. Each change goes straight back
/// to the profile.
private struct WidgetSettingsMenu: View {
    let tile: WidgetTile
    let update: (WidgetTile) -> Void

    @ObservedObject private var accessories = AccessoryBatteryMonitor.shared
    @ObservedObject private var macBattery = BatteryMonitor.shared

    var body: some View {
        switch tile.kind {
        case .folderStack:
            Button("Choose Folder…", action: chooseFolder)
        case .appStack:
            Button("Add Apps…", action: chooseApps)
            if !tile.stack.isEmpty {
                Menu("Remove App") {
                    ForEach(tile.stack) { entry in
                        Button(entry.title) { edit { $0.stack.removeAll { $0.id == entry.id } } }
                    }
                }
            }
        case .launcher:
            // The name and the arguments are typed on the card in the editor.
            Button(tile.path == nil ? "Choose App…" : "Change App…", action: chooseApp)
            if let identifier = tile.appURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }),
               BrowserProfiles.isBrowser(identifier) {
                let profiles = BrowserProfiles.profiles(of: identifier)
                if !profiles.isEmpty {
                    Picker("Profile", selection: browserProfile(among: profiles)) {
                        Text("None").tag(String?.none)
                        ForEach(profiles) { profile in
                            Label { Text(profile.name) } icon: { Image(nsImage: profile.image) }
                                .tag(String?.some(profile.id))
                        }
                    }
                }
            }
            Divider()
            Button("Choose Icon…", action: chooseIcon)
            if tile.iconPath != nil {
                Button("Use App's Icon") { edit { $0.iconPath = nil } }
            }
        case .agents:
            Picker("Layout", selection: binding(\.agentsLayout)) {
                ForEach(AgentsLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        case .nowPlaying:
            Picker("Layout", selection: binding(\.nowPlayingLayout)) {
                ForEach(NowPlayingLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Show Previous and Next Buttons", isOn: binding(\.showsControls))
        case .aiUsage:
            Picker("Layout", selection: binding(\.usageLayout)) {
                ForEach(UsageLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            ForEach(UsageService.allCases) { service in
                Toggle(service.title, isOn: tracks(service))
            }
        case .accessories:
            Picker("Layout", selection: binding(\.accessoryLayout)) {
                ForEach(AccessoryLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            if macBattery.status != nil {
                Toggle("This Mac", isOn: binding(\.showsMacBattery))
            }
            ForEach(accessories.devices) { device in
                Toggle("\(device.name) — \(device.level)%", isOn: shows(device.id))
            }
        default:
            EmptyView()
        }
    }

    private func edit(_ change: (inout WidgetTile) -> Void) {
        var changed = tile
        change(&changed)
        update(changed)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WidgetTile, Value>) -> Binding<Value> {
        Binding(
            get: { tile[keyPath: keyPath] },
            set: { value in edit { $0[keyPath: keyPath] = value } }
        )
    }

    /// Ticking a service on puts it back in its usual place among the others.
    private func tracks(_ service: UsageService) -> Binding<Bool> {
        Binding(
            get: { tile.usageServices.contains(service) },
            set: { on in
                edit { tile in
                    if on {
                        tile.usageServices = UsageService.allCases.filter { $0 == service || tile.usageServices.contains($0) }
                    } else {
                        tile.usageServices.removeAll { $0 == service }
                    }
                }
            }
        )
    }

    private func shows(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !tile.hiddenAccessoryIDs.contains(id) },
            set: { on in
                edit { tile in
                    if on {
                        tile.hiddenAccessoryIDs.removeAll { $0 == id }
                    } else if !tile.hiddenAccessoryIDs.contains(id) {
                        tile.hiddenAccessoryIDs.append(id)
                    }
                }
            }
        )
    }

    // The dock never takes focus, so a panel opened from it needs the app brought
    // forward first, or it comes up behind whatever is in front.
    private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let path = tile.path { panel.directoryURL = URL(fileURLWithPath: path) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        edit { $0.path = url.path }
    }

    private func chooseApps() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        edit { tile in
            for url in panel.urls where url.pathExtension == "app" {
                guard !tile.apps.contains(where: { $0.path == url.path }), let app = DockTile.app(at: url) else { continue }
                tile.stack.append(.app(app))
            }
        }
    }

    private func chooseApp() {
        NSApp.activate(ignoringOtherApps: true)
        guard let url = LauncherPanels.chooseApp(near: tile.path) else { return }
        edit { $0.setApp(at: url) }
    }

    private func chooseIcon() {
        NSApp.activate(ignoringOtherApps: true)
        guard let url = LauncherPanels.chooseIcon() else { return }
        edit { $0.iconPath = url.path }
    }

    /// The chosen profile by id — with its name kept beside it for the tile.
    private func browserProfile(among profiles: [BrowserProfile]) -> Binding<String?> {
        Binding(
            get: { tile.browserProfile?.id },
            set: { id in
                edit { $0.browserProfile = profiles.first { $0.id == id }.map { BrowserProfileRef(id: $0.id, name: $0.name) } }
            }
        )
    }
}

/// The open panels a launcher is set up with, shared by its card in the editor
/// and its menu on the dock.
enum LauncherPanels {
    /// An app, starting from the one already chosen.
    @MainActor
    static func chooseApp(near path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = path.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// An image file, or an app whose icon to borrow.
    @MainActor
    static func chooseIcon() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .application]
        panel.prompt = "Choose"
        panel.message = "Choose an image, or an app to borrow the icon of"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

extension View {
    func dockContextMenu<Items: View>(@ViewBuilder items: () -> Items) -> some View {
        modifier(DockContextMenu(items: items()))
    }
}

// MARK: - The dock

/// Whether a tile is being dragged on any dock. An auto-hiding dock stays put
/// meanwhile: a tile carried off it to be removed takes the pointer well away.
@MainActor
enum DockDrag {
    static var inProgress = false
}

/// The custom dock: a translucent slab, like the Dock, holding app tiles and
/// widgets in one row — or one column, on a left or right edge. Shown live in
/// `CustomDockWindowController`'s panel and as the preview in the editor.
struct CustomDockView: View {
    let items: [DockStripItem]
    var others: [DockTile] = []
    var showsRunningApps = false
    /// The Dock's notification badges on the app tiles, read while the dock is up.
    var showsBadges = false
    var edge: DockStripEdge = .bottom
    /// Which end of its edge the dock hugs; the grip and the pager sit at the other.
    var alignment: DockStripAlignment = .center
    var tileSize: CGFloat = 56
    /// How much a tile under the pointer grows, in points; zero for no magnification.
    var magnificationExtra: CGFloat = 0
    var look = DockLook()
    /// The profile's colour, washed over the slab when the look asks for it.
    var tint: Color? = nil
    /// The most room the screen has for the slab along its edge, the headroom for
    /// magnification left out. Nil in the editor's preview, which has no screen.
    var screenLength: CGFloat? = nil
    /// The length the profile caps the slab at, if any; see `CustomDockOptions.maxLength`.
    var maxLength: CGFloat? = nil
    /// Called with the new order when an item is dragged to a new place, as the
    /// Dock's own tiles can be. Without it the items stay put.
    var onReorder: (([DockStripItem]) -> Void)? = nil
    /// Called with the new cap when the grip at the end of the dock is dragged —
    /// nil for none. Without it there is no grip.
    var onResize: ((CGFloat?) -> Void)? = nil

    @ObservedObject private var running = RunningAppsMonitor.shared
    /// Where the pointer is over the dock, along its axis, in the dock's own space.
    @State private var pointer: CGFloat?
    /// Each item's slot in the dock's space, reported by the items themselves.
    @State private var frames: [UUID: CGRect] = [:]

    // Reordering
    /// The item being held and dragged, and where the pointer is along the axis.
    @State private var dragging: UUID?
    @State private var dragLocation: CGFloat = 0
    /// The order as the drag has it so far; kept after the drop until `items` catches up.
    @State private var pendingOrder: [DockStripItem]?
    /// The held item and the slot it was lifted from, for the ghost; it may have
    /// left `pendingOrder` while it is carried off the dock.
    @State private var heldItem: DockStripItem?
    @State private var heldSlot: CGRect = .zero
    /// The held item is off the dock: letting go now removes it, as in the Dock.
    @State private var removing = false
    /// The held item — an app or a launcher — is over the middle of a stack:
    /// letting go folds it into the stack.
    @State private var dropTarget: UUID?
    /// The dock's frame in the hosting view, to place mouse events from `dragMonitor`.
    @State private var frameInHost: CGRect = .zero
    /// Follows the mouse once a drag has begun. The gesture alone stops at the
    /// panel's edge, and a removal takes the pointer well past it.
    @State private var dragMonitor: Any?
    /// The divider's slot, so a running app dropped before it is pinned.
    private static let dividerID = UUID()

    // Overflow
    /// The strip's length as laid out, magnified tiles and all.
    @State private var measuredLength: CGFloat = 0
    /// The strip is longer than the slab may be: it scrolls, with the pager at the end.
    @State private var overflowing = false
    /// How far the strip has scrolled, while it overflows.
    @State private var scrollOffset: CGFloat = 0
    /// The cap as the grip is dragged, ahead of the profile.
    @State private var draftMax: CGFloat?
    /// Where the pointer and the slab's length were when the grip was taken hold of.
    @State private var gripStart: (mouse: CGFloat, length: CGFloat)?
    @State private var gripHovered = false

    @Environment(\.colorScheme) private var systemColorScheme
    /// Set on the live dock only; the editor's preview has none.
    @Environment(\.dockSettingsAction) private var settingsAction
    @Environment(\.dockLayoutChanged) private var relayout
    @ObservedObject private var accessibility = AccessibilityDisplay.shared

    private var vertical: Bool { edge.isVertical }
    private var style: DockStyle { look.style }
    /// The slab's inset and the gap between tiles; a column sits a little tighter.
    private var padding: CGFloat { look.density.padding * (vertical ? 0.75 : 1) }
    private var cornerRadius: CGFloat { padding + 10 }
    private var displayedItems: [DockStripItem] { pendingOrder ?? items }
    /// Each item's centre along the axis.
    private var centers: [UUID: CGFloat] { frames.mapValues { vertical ? $0.midY : $0.midX } }

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: padding)) : AnyLayout(HStackLayout(spacing: padding))
        // The reader is wrapped round the pager as well as the strip, so its
        // buttons can scroll the strip.
        ScrollViewReader { proxy in
            layout {
                if controlsAtStart {
                    grip
                    if overflowing { pager(proxy) }
                }
                if overflowing {
                    ScrollView(vertical ? .vertical : .horizontal) {
                        strip.background(GeometryReader { geometry in
                            let frame = geometry.frame(in: .named("scroll"))
                            Color.clear.preference(key: ScrollOffsetKey.self, value: CGFloat?.some(-(vertical ? frame.minY : frame.minX)))
                        })
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: vertical ? nil : window, height: vertical ? window : nil)
                    .coordinateSpace(name: "scroll")
                } else {
                    strip
                }
                if !controlsAtStart {
                    if overflowing { pager(proxy) }
                    grip
                }
            }
        }
        .padding(padding)
        // Between the tiles and the plate: behind the tiles' own menus, in front
        // of the material, which would otherwise take the click.
        .modifier(SlabContextMenu())
        .background(plate)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // A forced light or dark style colours the tiles and cards too, not just the
        // slab. The panel sets the same appearance on its window; this covers the
        // preview in the editor, whose window keeps the system's.
        .environment(\.colorScheme, style.forcedColorScheme ?? systemColorScheme)
        .environment(\.dockTileCards, look.drawsTileCards)
        .environment(\.dockShowsBadges, showsBadges)
        .modifier(BadgeSubscription(active: showsBadges))
        // Over the whole slab, padding included, as the Dock magnifies; the pointer
        // is placed against the strip's own frame, which scrolls.
        .onContinuousHover(coordinateSpace: .global) { phase in
            guard magnificationExtra > 0, dragging == nil, gripStart == nil else { return }
            switch phase {
            case .active(let point): pointer = vertical ? point.y - frameInHost.minY : point.x - frameInHost.minX
            case .ended: pointer = nil
            }
        }
        .onPreferenceChange(TileFrameKey.self) { frames = $0 }
        .onPreferenceChange(HostFrameKey.self) { frameInHost = $0 }
        .onPreferenceChange(StripLengthKey.self) { measuredLength = $0 }
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 ?? 0 }
        .onChange(of: items) { pendingOrder = nil }
        .onChange(of: naturalLength) { updateOverflow() }
        .onChange(of: cap) { updateOverflow() }
        // Capped, the slab's length is the dock's own doing; the panel follows it.
        .onChange(of: overflowing ? cap : nil) { relayout?() }
        // The profile has taken the dragged cap; the draft has done its job.
        .onChange(of: maxLength) { draftMax = nil }
        .environment(\.dockTileSize, tileSize)
        .environment(\.dockSlabInset, padding)
        .environment(\.dockVertical, vertical)
        .environment(\.dockEdge, edge)
    }

    /// The tiles and widgets in their row, the ghost of a held one over them.
    private var strip: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: padding)) : AnyLayout(HStackLayout(spacing: padding))
        return layout {
            ForEach(displayedItems) { item in
                reorderable(item)
            }
            if showsRunningApps {
                // A running app being dragged takes a slot in the row as well, but its
                // view here must live on: the gesture is attached to it.
                let unpinned = unpinned
                if !unpinned.isEmpty {
                    divider.background(CenterReporter(id: Self.dividerID, vertical: vertical))
                    ForEach(unpinned) { tile in
                        reorderable(.tile(tile), inRunningSection: true)
                    }
                }
            }
            if !others.isEmpty {
                divider
                ForEach(others) { tile in
                    itemView(.tile(tile))
                }
            }
        }
        .overlay(ghost)
        .background(GeometryReader { geometry in
            Color.clear
                .preference(key: HostFrameKey.self, value: geometry.frame(in: .global))
                .preference(key: StripLengthKey.self, value: vertical ? geometry.size.height : geometry.size.width)
        })
        .coordinateSpace(name: "dock")
    }

    private var unpinned: [DockTile] {
        showsRunningApps ? running.unpinnedTiles(excluding: items.compactMap(\.tile)) : []
    }

    // MARK: - Overflow

    /// The grip and the pager sit at the end of the dock that is free to move: the
    /// trailing end, or the leading one when the dock hugs the trailing end of its
    /// edge. A column is centred, so its bottom end.
    private var controlsAtStart: Bool { !vertical && alignment == .trailing }
    private var hasGrip: Bool { onResize != nil }
    /// The grip's slot along the dock; the line itself is thinner.
    private var gripLength: CGFloat { hasGrip ? 10 : 0 }
    private var pagerLength: CGFloat { DockPagerButton.length * 2 + 2 }

    /// The strip's length at rest: what was measured, less the growth of any tiles
    /// magnified at the moment, so a pointer on the dock does not change what fits.
    private var naturalLength: CGFloat {
        (measuredLength - magnificationGrowth).rounded()
    }

    /// How much longer the magnified tiles make the strip right now. Only app tiles
    /// magnify, each padding its slot by its growth.
    private var magnificationGrowth: CGFloat {
        guard magnificationExtra > 0, let pointer else { return 0 }
        let tiles = displayedItems.compactMap(\.tile) + unpinned + others
        return tiles.reduce(0) { total, tile in
            guard !tile.kind.isSpacer else { return total }
            let scale = Magnify.scale(pointer: pointer, center: centers[tile.id], extra: magnificationExtra, size: tileSize)
            return total + tileSize * (scale - 1)
        }
    }

    /// The shortest the slab can be: room for a tile and a half beside the controls.
    private var minLength: CGFloat {
        padding * 2 + tileSize * 1.5 + padding + pagerLength + (hasGrip ? gripLength + padding : 0)
    }

    /// The longest the slab may be right now: the cap being dragged, else the
    /// tighter of the profile's and the screen's. Nil for no limit.
    private var cap: CGFloat? {
        if let draftMax { return draftMax }
        let limit = [maxLength, screenLength].compactMap { $0 }.min()
        return limit.map { max($0, minLength) }
    }

    /// The slab's length while the strip fits: the strip with the padding and the
    /// grip around it.
    private var restLength: CGFloat {
        naturalLength + padding * 2 + (hasGrip ? gripLength + padding : 0)
    }

    /// The strip's visible length while it overflows: the cap less everything else
    /// on the slab.
    private var window: CGFloat {
        guard let cap else { return 0 }
        return max(cap - padding * 2 - pagerLength - padding - (hasGrip ? gripLength + padding : 0), 1)
    }

    /// Whether the strip fits, with a little give so a tile magnified at the
    /// boundary does not flip the pager on and off.
    private func updateOverflow() {
        guard let cap else { overflowing = false; return }
        if overflowing {
            if restLength <= cap - 4 { overflowing = false }
        } else if restLength > cap + 0.5 {
            overflowing = true
        }
    }

    private var canPageBack: Bool { scrollOffset > 1 }
    private var canPageForward: Bool { scrollOffset + window < measuredLength - 1 }

    /// The arrows through the rest of the strip: a page at a time, aligned to the
    /// tiles so none is left cut in half.
    private func pager(_ proxy: ScrollViewProxy) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            DockPagerButton(systemName: vertical ? "chevron.up" : "chevron.left", enabled: canPageBack) {
                page(proxy, forward: false)
            }
            DockPagerButton(systemName: vertical ? "chevron.down" : "chevron.right", enabled: canPageForward) {
                page(proxy, forward: true)
            }
        }
    }

    private func page(_ proxy: ScrollViewProxy, forward: Bool) {
        let start = scrollOffset
        let end = start + window
        // The divider has no id of its own to scroll to.
        let slots = frames.filter { $0.key != Self.dividerID }.map { id, frame in
            (id: id, from: vertical ? frame.minY : frame.minX, to: vertical ? frame.maxY : frame.maxX)
        }
        let target: UUID?
        let anchor: UnitPoint
        if forward {
            // The first slot cut off at the far end comes to the near end.
            target = slots.filter { $0.to > end + 1 }.min { $0.from < $1.from }?.id
            anchor = vertical ? .top : .leading
        } else {
            // The first slot cut off at the near end goes to the far end.
            target = slots.filter { $0.from < start - 1 }.max { $0.from < $1.from }?.id
            anchor = vertical ? .bottom : .trailing
        }
        guard let target else { return }
        DockTooltipController.shared.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: anchor) }
    }

    /// The grip at the end of the dock: a slim line, dragged along the edge to set
    /// how long the slab may be. Dragged out to the strip's own length — or as far
    /// as the screen goes — it lifts the limit; so does a double-click.
    @ViewBuilder
    private var grip: some View {
        if hasGrip {
            let active = gripHovered || gripStart != nil
            Capsule(style: .continuous)
                .fill(DockPalette.onSlab.opacity(active ? 0.55 : 0.22))
                .frame(width: vertical ? tileSize * 0.5 : 3, height: vertical ? 3 : tileSize * 0.5)
                .frame(width: vertical ? nil : gripLength, height: vertical ? gripLength : nil)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: active)
                .onHover { hovering in
                    gripHovered = hovering
                    if hovering { (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() }
                }
                // The dock can go away under the pointer — a profile switch, say —
                // and the arrow must not stay a resize cursor.
                .onDisappear { if gripHovered { gripHovered = false; NSCursor.pop() } }
                .dockTooltip(
                    vertical ? "Dock height" : "Dock width",
                    "Drag to limit it; double-click for all of it"
                )
                .onTapGesture(count: 2) { onResize?(nil) }
                .gesture(gripGesture)
        }
    }

    /// The drag is read from the screen rather than the window: the panel moves
    /// under the pointer as the dock changes length.
    private var gripGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                let along = vertical ? mouse.y : mouse.x
                if gripStart == nil {
                    gripStart = (mouse: along, length: overflowing ? (cap ?? restLength) : restLength)
                    pointer = nil
                    DockTooltipController.shared.cancel()
                }
                guard let gripStart else { return }
                // Screen y runs up; the grip is at a column's bottom end.
                let outward: CGFloat = vertical || controlsAtStart ? -1 : 1
                let length = gripStart.length + (along - gripStart.mouse) * outward
                draftMax = min(max(length, minLength), screenLength ?? .infinity)
            }
            .onEnded { _ in
                guard let draft = draftMax else { gripStart = nil; return }
                gripStart = nil
                // Out to where the strip fits, or as far as the screen goes, is no limit at all.
                let free = min(restLength, screenLength ?? .infinity)
                let committed: CGFloat? = draft >= free - 0.5 ? nil : draft.rounded()
                if committed == maxLength {
                    draftMax = nil
                } else {
                    onResize?(committed)
                    // The new cap arrives through the profile; if for any reason it
                    // does not, the dock goes back to what it was given.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        if gripStart == nil { draftMax = nil }
                    }
                }
            }
    }

    /// The slab behind the tiles — nothing at all when the look is transparent.
    @ViewBuilder
    private var plate: some View {
        if style.hasPlate {
            DockSlab(look: look, tint: tint, cornerRadius: cornerRadius)
        }
    }

    private func magnify(_ id: UUID) -> Magnify {
        Magnify(id: id, pointer: pointer, centers: centers, extra: magnificationExtra, size: tileSize, edge: edge)
    }

    // MARK: - Reordering

    /// An item that can be held and dragged along the dock, the Dock's way: press
    /// for a moment, then move. The others shuffle aside as it passes their centres,
    /// and letting go writes the new order back through `onReorder`. A plain click
    /// still reaches the tile. A running app after the divider drags the same way:
    /// dropped before the divider it joins the profile, as in the Dock; dropped
    /// after it, it stays where it was. A pinned app carried off the dock is
    /// removed from the profile when let go, as in the Dock.
    private func reorderable(_ item: DockStripItem, inRunningSection: Bool = false) -> some View {
        let held = dragging == item.id
        // While held, the item's slot stays in the row — invisible, shuffling with the
        // others — and the item itself is drawn as the ghost under the pointer. A held
        // running app has a slot in the row too; that one reports the frame.
        let reportsFrame = !(held && inRunningSection)
        return itemView(item)
            .environment(\.dockPinAction, inRunningSection && onReorder != nil ? { pin(item) } : nil)
            .background(reportsFrame ? CenterReporter(id: item.id, vertical: vertical) : nil)
            .opacity(held ? 0 : 1)
            // The tile under the pointer must not act when the drag lets go on it.
            .allowsHitTesting(!held)
            .simultaneousGesture(reorderGesture(item), including: onReorder == nil ? .subviews : .all)
    }

    /// The held item, lifted and following the pointer along the dock, centred across
    /// it and kept inside the slab so it is never cut off at the ends.
    @ViewBuilder
    private var ghost: some View {
        if dragging != nil, let item = heldItem {
            GeometryReader { geometry in
                let half = (vertical ? heldSlot.height : heldSlot.width) / 2 * 1.08
                let length = vertical ? geometry.size.height : geometry.size.width
                let along = min(max(dragLocation, half), max(half, length - half))
                itemView(item)
                    .scaleEffect(removing ? 0.9 : 1.08)
                    .opacity(removing ? 0.55 : 1)
                    .overlay {
                        if removing || dropTarget != nil {
                            Text(removing ? "Remove" : "Add to Stack")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.75)))
                                .fixedSize()
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    .animation(.easeOut(duration: 0.12), value: removing)
                    .position(
                        x: vertical ? geometry.size.width / 2 : along,
                        y: vertical ? along : geometry.size.height / 2
                    )
            }
            .allowsHitTesting(false)
            .transition(.identity)
        }
    }

    private func reorderGesture(_ item: DockStripItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("dock")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging != item.id { beginDrag(item) }
                guard let drag else { return }
                dragMoved(to: drag.location)
            }
            .onEnded { _ in endDrag() }
    }

    /// The pointer has moved to `point`, in the dock's space.
    private func dragMoved(to point: CGPoint) {
        guard let item = heldItem else { return }
        dragLocation = vertical ? point.y : point.x
        // Well clear of the slab across the dock, the drag becomes a removal.
        let across = vertical ? point.x : point.y
        let slotAcross = vertical ? heldSlot.midX : heldSlot.midY
        removing = canRemove(item) && abs(across - slotAcross) > tileSize * 0.9
        // Over the middle of a stack the row holds still — no shuffling past it —
        // and the stack is the target. The middle rather than the whole tile, so
        // the slot still moves to either side of a stack as it does past any tile.
        dropTarget = removing ? nil : stackUnder(dragLocation, holding: item)
        if dropTarget == nil { shuffle(item.id) }
    }

    /// The stack whose middle third the pointer is over, if the held item is one
    /// a stack takes — an app tile, or a launcher.
    private func stackUnder(_ along: CGFloat, holding item: DockStripItem) -> UUID? {
        guard onReorder != nil, Self.stackEntry(for: item) != nil else { return nil }
        return displayedItems.first { other in
            guard other.id != item.id, other.widget?.kind == .appStack, let frame = frames[other.id] else { return false }
            let centre = vertical ? frame.midY : frame.midX
            let length = vertical ? frame.height : frame.width
            return abs(along - centre) < length / 3
        }?.id
    }

    /// What the item becomes in a stack; nil for one a stack does not take.
    private static func stackEntry(for item: DockStripItem) -> AppStackEntry? {
        switch item {
        case .tile(let tile): return tile.kind == .app ? .app(tile) : nil
        case .widget(let widget): return widget.kind == .launcher ? .launcher(widget) : nil
        }
    }

    /// Folds the item into the stack with the id: out of the row, if it was in
    /// it, and onto the end of the stack's entries. With nil, into a new stack
    /// where the item was — or at the end of the row, for a running app that
    /// was not in it — keeping a launcher's anchor so the stack stays put in a
    /// combined dock.
    private func fold(_ item: DockStripItem, into stackID: UUID?) {
        guard let entry = Self.stackEntry(for: item) else { return }
        var row = items.filter { $0.id != item.id }
        if let stackID {
            guard let index = row.firstIndex(where: { $0.id == stackID }), var stack = row[index].widget else { return }
            stack.stack.append(entry)
            row[index] = .widget(stack)
        } else {
            var stack = WidgetTile(kind: .appStack)
            stack.stack = [entry]
            if let launcher = item.widget { stack.anchor = launcher.anchor }
            row.insert(.widget(stack), at: items.firstIndex { $0.id == item.id } ?? row.count)
        }
        onReorder?(row)
    }

    /// AppKit keeps sending the drag to the window the mouse went down in, wherever
    /// the pointer goes; SwiftUI's gesture only reports it inside the window. So
    /// once a drag has begun the events are read directly, in the hosting view's
    /// (flipped, top-left) space, and placed against the dock's frame in it.
    private func installDragMonitor() {
        removeDragMonitor()
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                guard let host = event.window?.contentView else { return }
                let inHost = host.convert(event.locationInWindow, from: nil)
                let point = CGPoint(x: inHost.x - frameInHost.minX, y: inHost.y - frameInHost.minY)
                if event.type == .leftMouseUp {
                    dragMoved(to: point)
                    endDrag()
                } else {
                    dragMoved(to: point)
                }
            }
            return event
        }
    }

    private func removeDragMonitor() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
    }

    private func beginDrag(_ item: DockStripItem) {
        dragging = item.id
        DockDrag.inProgress = true
        installDragMonitor()
        heldItem = item
        heldSlot = frames[item.id] ?? .zero
        removing = false
        dropTarget = nil
        dragLocation = centers[item.id] ?? 0
        // A running app lifts out of its section and takes a slot at the end of the
        // row, just before the divider, until it is carried past a pinned item.
        pendingOrder = items.contains(where: { $0.id == item.id }) ? items : items + [item]
        pointer = nil
        DockTooltipController.shared.cancel()
        DockStackController.shared.dismiss()
    }

    /// Puts the held item after every other item whose centre the pointer has passed.
    /// Since the others shift by the held item's width when it moves, the centre just
    /// passed ends up further away, which keeps the order from flickering back.
    private func shuffle(_ id: UUID) {
        guard let item = heldItem else { return }
        var order = displayedItems.filter { $0.id != id }
        // Off the dock, the item's slot closes; back over it, the slot reopens
        // wherever the pointer is.
        if !removing {
            let target = order.filter { (centers[$0.id] ?? .infinity) < dragLocation }.count
            order.insert(item, at: target)
        }
        guard order.map(\.id) != displayedItems.map(\.id) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { pendingOrder = order }
    }

    private func endDrag() {
        guard let dragging else { return }
        self.dragging = nil
        DockDrag.inProgress = false
        removeDragMonitor()
        // A running app is pinned only when let go before the divider — anywhere in
        // the row, or the gap just before the divider. Elsewhere it goes back.
        let wasRunning = !items.contains { $0.id == dragging }
        if wasRunning, removing || dragLocation >= centers[Self.dividerID] ?? .infinity {
            pendingOrder = nil
            return
        }
        if removing {
            removing = false
            remove(dragging)
            return
        }
        if let dropTarget, let item = heldItem {
            self.dropTarget = nil
            pendingOrder = nil
            withAnimation(.easeInOut(duration: 0.15)) { fold(item, into: dropTarget) }
            return
        }
        if let order = pendingOrder, order.map(\.id) != items.map(\.id) {
            onReorder?(order)
            // The new items arrive through the profile; if for any reason they do
            // not, the dock goes back to what it was given.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                // `dragging` here is the guard's copy; the state is what says
                // whether another drag has begun since.
                if self.dragging == nil { pendingOrder = nil }
            }
        } else {
            pendingOrder = nil
        }
    }

    /// The Dock's own hairline between sections.
    private var divider: some View {
        Rectangle()
            .fill(DockPalette.onSlab.opacity(0.18))
            .frame(width: vertical ? tileSize * 0.6 : 1, height: vertical ? 1 : tileSize * 0.6)
            .padding(vertical ? .vertical : .horizontal, 2)
    }

    /// Only app icons magnify, as in the Dock; a widget card keeps its size and its
    /// place, and the icons around it still respond to the pointer.
    @ViewBuilder
    private func itemView(_ item: DockStripItem) -> some View {
        // Only what is in the profile can be removed; a running app after the
        // divider is not in it to begin with.
        let removable = onReorder != nil && items.contains { $0.id == item.id }
        Group {
            switch item {
            case .widget(let widget):
                WidgetTileView(tile: widget)
            case .tile(let tile):
                if tile.kind.isSpacer {
                    let gap: CGFloat = tile.kind == .smallSpacer ? 6 : (vertical ? 12 : 24)
                    Color.clear.frame(width: vertical ? 1 : gap, height: vertical ? gap : 1)
                } else {
                    AppTileView(tile: tile).modifier(magnify(tile.id))
                }
            }
        }
        .environment(\.dockRemoveAction, removable ? { remove(item.id) } : nil)
        .environment(\.dockStacking, stacking(for: item))
        .environment(\.dockStackTargeted, dropTarget == item.id)
    }

    /// Add to Stack for an app tile or a launcher, when the row can be rearranged:
    /// the other stacks in the row to join, or a new one in the tile's place. A
    /// running app after the divider can be stacked too; it joins the profile
    /// that way, as a drag onto a stack puts it there.
    private func stacking(for item: DockStripItem) -> DockStacking? {
        guard onReorder != nil, Self.stackEntry(for: item) != nil else { return nil }
        let stacks = items.compactMap(\.widget).filter { $0.kind == .appStack && $0.id != item.id }
        return DockStacking(stacks: stacks) { stackID in
            withAnimation(.easeInOut(duration: 0.15)) { fold(item, into: stackID) }
        }
    }

    /// Puts a running app into the profile, at the end: Keep in Dock. The same
    /// place a drag across the divider lands it before it is carried further.
    private func pin(_ item: DockStripItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        onReorder?(items + [item])
    }

    /// Takes an item out of the profile: Remove from Dock, or a drag off the dock.
    private func remove(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        onReorder?(items.filter { $0.id != id })
    }

    /// Anything in the profile can be dragged off the live dock. Not in the editor's
    /// preview, which sits in a window of its own where the drag's geometry differs
    /// and which has its own remove buttons.
    private func canRemove(_ item: DockStripItem) -> Bool {
        onReorder != nil && settingsAction != nil && items.contains { $0.id == item.id }
    }
}

/// The slab's own context menu, for a right-click between the tiles: just the
/// settings item, and only on the live dock. Behind the tiles, so theirs win.
private struct SlabContextMenu: ViewModifier {
    @Environment(\.dockSettingsAction) private var openSettings
    @Environment(\.dockEdge) private var edge

    func body(content: Content) -> some View {
        if let openSettings {
            content.background(DockMenuAnchor(edge: edge, atPointer: true) {
                let menu = NSMenu()
                menu.addItem("Custom Dock Settings…") { openSettings() }
                return menu
            })
        } else {
            content
        }
    }
}

/// One of the pager's arrows: quiet on the slab, brighter under the pointer,
/// dimmed when there is nothing further that way.
private struct DockPagerButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    @Environment(\.dockTileSize) private var tileSize
    @State private var hovering = false

    /// Each arrow's slot along the dock.
    static let length: CGFloat = 18

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: max(9, tileSize * 0.2), weight: .semibold))
                .foregroundStyle(DockPalette.onSlab.opacity(enabled ? (hovering ? 0.95 : 0.7) : 0.25))
                .frame(width: Self.length, height: Self.length)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

// MARK: - Magnification

/// Reports where an item's slot is in the dock, for magnification and reordering.
private struct CenterReporter: View {
    let id: UUID
    let vertical: Bool

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: TileFrameKey.self, value: [id: geometry.frame(in: .named("dock"))])
        }
    }
}

/// The strip's length along the dock, as laid out. The strip has siblings on the
/// slab — the grip, the pager — that report nothing; they must not blank it out.
private struct StripLengthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// How far the strip has scrolled, while it overflows. Nil until it reports.
private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

private struct HostFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct TileFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Grows a tile by how close the pointer is, anchored on the dock's edge so it
/// rises out of the slab, and pads it so its neighbours are pushed aside — the
/// Dock's magnification, near enough.
private struct Magnify: ViewModifier {
    let id: UUID
    let pointer: CGFloat?
    let centers: [UUID: CGFloat]
    let extra: CGFloat
    let size: CGFloat
    let edge: DockStripEdge

    /// Tiles this many widths away from the pointer are back at full size.
    private static let reach: CGFloat = 2.5

    private var scale: CGFloat {
        Self.scale(pointer: pointer, center: centers[id], extra: extra, size: size)
    }

    /// How much a tile centred at `center` grows with the pointer at `pointer`.
    static func scale(pointer: CGFloat?, center: CGFloat?, extra: CGFloat, size: CGFloat) -> CGFloat {
        guard extra > 0, let pointer, let center else { return 1 }
        let distance = abs(pointer - center) / size
        guard distance < reach else { return 1 }
        let t = 1 - distance / reach
        return 1 + (extra / size) * t * t * (3 - 2 * t)  // smoothstep
    }

    private var anchor: UnitPoint {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    func body(content: Content) -> some View {
        let scale = scale
        content
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: TileFrameKey.self, value: [id: geometry.frame(in: .named("dock"))])
                }
            )
            .scaleEffect(scale, anchor: anchor)
            .padding(edge.isVertical ? .vertical : .horizontal, size * (scale - 1) / 2)
            .animation(.easeOut(duration: 0.1), value: scale)
    }
}

// MARK: - App tiles

/// One app, folder or link from the profile: click to open or bring forward, with
/// the Dock's running dot underneath — or beside it, in a column.
private struct AppTileView: View {
    let tile: DockTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @Environment(\.dockShowsBadges) private var showsBadges
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockPinAction) private var pin
    @Environment(\.dockRemoveAction) private var remove
    @Environment(\.dockStacking) private var stacking
    @Environment(\.dockSettingsAction) private var openSettings
    @Environment(\.dockSlabInset) private var slabInset
    @ObservedObject private var running = RunningAppsMonitor.shared
    @ObservedObject private var badges = DockBadgeMonitor.shared
    @State private var hovering = false

    var body: some View {
        let dotRoom: CGFloat = 8
        let layout = vertical ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        Button(action: open) {
            layout {
                icon
                    .frame(width: size - dotRoom, height: size - dotRoom)
                    .overlay(alignment: .topTrailing) { badge }
                    .scaleEffect(hovering ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                Circle()
                    .fill(DockPalette.onSlab.opacity(running.isRunning(tile) ? 0.85 : 0))
                    .frame(width: 4, height: 4)
                    .frame(width: vertical ? dotRoom : nil, height: vertical ? nil : dotRoom)
            }
            .frame(width: vertical ? size : nil, height: vertical ? nil : size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dockTooltip(tile.label, tile.isMissing ? "Moved or deleted" : nil)
        .overlay(DockMenuAnchor(edge: edge, inset: slabInset, build: buildMenu))
    }

    @ViewBuilder
    private var icon: some View {
        if let icon = tile.icon {
            Image(nsImage: icon).resizable()
        } else {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(DockPalette.onSlab.opacity(0.12))
                .overlay(
                    Image(systemName: tile.isMissing ? "questionmark" : tile.kind.symbolName)
                        .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                )
        }
    }

    /// The Dock's badge, on the icon's corner as the Dock draws it.
    @ViewBuilder
    private var badge: some View {
        if showsBadges, let label = badges.label(for: tile) {
            NotificationBadge(label: label)
                .offset(x: size * 0.06, y: -size * 0.06)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var url: URL? { tile.url }

    private func open() {
        DockTooltipController.shared.cancel()
        tile.open()
    }

    /// The Dock's menu for an app tile, near enough: its open windows, then its
    /// New Window and a browser's profiles, then Options, then Show All Windows,
    /// Hide and Quit;
    /// for one that is not running, the profiles, Options and Open — after
    /// Remove from Dock, Add to Stack and the dock's settings, which come first. Recent
    /// documents are the one thing missing — macOS hands an app's list to that
    /// app alone. Built afresh on every right-click, so the windows and profiles
    /// are the ones there now.
    private func buildMenu() -> NSMenu {
        DockTooltipController.shared.cancel()
        let menu = NSMenu()
        // The dock's own items first, where they are found without scrolling past
        // the windows; the same place `DockContextMenu` gives the widgets.
        if let remove { menu.addItem("Remove from Dock") { remove() } }
        if let stacking { menu.addItem(stacking.menuItem) }
        if let openSettings { menu.addItem("Custom Dock Settings…") { openSettings() } }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        if tile.kind == .app {
            let instances = tile.bundleIdentifier.map {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).filter { !$0.isTerminated }
            } ?? []
            if let app = instances.first {
                addWindows(of: instances, to: menu)
                if let command = AppWindows.newWindow(of: app) {
                    menu.addItem(command.title) { command.perform() }
                }
                if let profiles { menu.addItem(profiles) }
                menu.addItem(options)
                menu.addItem(.separator())
                menu.addItem("Show All Windows") { AppWindows.showAll(of: app) }
                menu.addItem(app.isHidden ? "Show" : "Hide") {
                    for instance in instances { _ = instance.isHidden ? instance.unhide() : instance.hide() }
                }
                menu.addItem("Quit") { for instance in instances { instance.terminate() } }
            } else {
                if let profiles { menu.addItem(profiles) }
                menu.addItem(options)
                menu.addItem(.separator())
                menu.addItem("Open") { open() }
            }
        } else if let url, url.isFileURL {
            menu.addItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        // A tile with nothing of its own would end on the separator.
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }

    /// The open windows of every running instance of the app, as the Dock lists
    /// them: a check mark on the one in front, a diamond on a minimized one, and
    /// choosing one brings it forward — the way to a particular window when an
    /// app has several. Read through Accessibility; without access, one item
    /// that leads to it. Ends in a divider when it has anything, so an app with
    /// no windows up does not start its menu with one.
    private func addWindows(of instances: [NSRunningApplication], to menu: NSMenu) {
        guard AppWindows.isAvailable else {
            menu.addItem("Show Windows Here…") {
                DockBadgeMonitor.shared.requestAccess()
                DockBadgeMonitor.openAccessibilitySettings()
            }
            menu.addItem(.separator())
            return
        }
        let windows = AppWindows.windows(of: instances)
        for window in windows {
            let item = menu.addItem(window.title) { window.raise() }
            if window.isFocused {
                item.state = .on
            } else if window.isMinimized {
                // The Dock's diamond, in the check mark's column.
                item.state = .mixed
                item.mixedStateImage = NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: "Minimized")?
                    .withSymbolConfiguration(.init(pointSize: 7, weight: .regular))
            }
        }
        if !windows.isEmpty { menu.addItem(.separator()) }
    }

    /// A browser's profiles, as its own Dock menu lists them: the account's
    /// picture or initial, a check mark on the ones with a window up, and
    /// choosing one opens a new window as that profile. Nil for any other app,
    /// and for a browser with no profiles to show.
    private var profiles: NSMenuItem? {
        guard let identifier = tile.bundleIdentifier, let url, BrowserProfiles.isBrowser(identifier) else { return nil }
        let profiles = BrowserProfiles.profiles(of: identifier)
        guard !profiles.isEmpty else { return nil }
        let submenu = NSMenu(title: "Profiles")
        for profile in profiles {
            let item = submenu.addItem(profile.name) { BrowserProfiles.open(profile, of: identifier, at: url) }
            item.image = profile.image
            item.state = profile.isOpen ? .on : .off
        }
        let item = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The Dock's Options submenu: Keep in Dock for a running app that is not in
    /// the profile, and Show in Finder.
    private var options: NSMenuItem {
        let submenu = NSMenu(title: "Options")
        if let pin { submenu.addItem("Keep in Dock") { pin() } }
        if let url, url.isFileURL {
            submenu.addItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        let item = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

/// A tile's context menu, opened where the Dock opens its: off the dock's
/// edge, on the far side of the tile and centred on it — or on the click, for
/// the slab, as the Dock does for its divider — rather than under the pointer.
/// From AppKit rather than SwiftUI, for two reasons: SwiftUI's context menu
/// only opens at the pointer, and it builds its items once and keeps them,
/// where an app's windows and a browser's profiles have to be read again each
/// time the menu opens, as the Dock does. Sits over the tile; a left click, a
/// hover or a drag goes through to the tile underneath.
private struct DockMenuAnchor: NSViewRepresentable {
    let edge: DockStripEdge
    /// From this view's edge out to the slab's, which the menu opens clear of.
    var inset: CGFloat = 0
    var atPointer: Bool = false
    let build: () -> NSMenu

    func makeNSView(context: Context) -> MenuView { MenuView() }

    func updateNSView(_ view: MenuView, context: Context) {
        view.edge = edge
        view.inset = inset
        view.atPointer = atPointer
        view.build = build
    }

    final class MenuView: NSView {
        var edge: DockStripEdge = .bottom
        var inset: CGFloat = 0
        var atPointer = false
        var build: (() -> NSMenu)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.opensMenu(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { open(event) }

        // A control-click opens the menu as a right-click does.
        override func mouseDown(with event: NSEvent) {
            if Self.opensMenu(event) { open(event) } else { super.mouseDown(with: event) }
        }

        private static func opensMenu(_ event: NSEvent) -> Bool {
            switch event.type {
            case .rightMouseDown, .rightMouseUp: return true
            case .leftMouseDown: return event.modifierFlags.contains(.control)
            default: return false
            }
        }

        /// Lays the menu's top-left corner where it sits clear of the slab on the
        /// dock's far side, centred across the tile, with a gap between; AppKit
        /// keeps the menu on screen from there. The view is not flipped: y runs up.
        private func open(_ event: NSEvent) {
            guard let menu = build?(), window != nil else { return }
            // SwiftUI puts a separator on each side of a `Section`, doubling the
            // one the menu has there. AppKit shows one, but `size` counts both —
            // a row's worth — and the menu would open that far from the dock.
            var lastWasSeparator = true
            for item in menu.items {
                if item.isSeparatorItem {
                    if lastWasSeparator { menu.removeItem(item) } else { lastWasSeparator = true }
                } else {
                    lastWasSeparator = false
                }
            }
            if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
            guard !menu.items.isEmpty else { return }
            let size = menu.size
            let click = convert(event.locationInWindow, from: nil)
            let centre = atPointer ? click : NSPoint(x: bounds.midX, y: bounds.midY)
            let gap = Self.gap + inset
            var corner: NSPoint
            switch edge {
            case .bottom: corner = NSPoint(x: centre.x - size.width / 2, y: bounds.maxY + gap + size.height)
            case .top: corner = NSPoint(x: centre.x - size.width / 2, y: bounds.minY - gap)
            case .leading: corner = NSPoint(x: bounds.maxX + gap, y: centre.y + size.height / 2)
            case .trailing: corner = NSPoint(x: bounds.minX - gap - size.width, y: centre.y + size.height / 2)
            }
            // AppKit meets the point with the first item's row, not the menu's edge,
            // so the menu lands that much higher than asked.
            corner.y -= Self.menuInset
            menu.popUp(positioning: nil, at: corner, in: self)
        }

        /// Between the slab's edge and the menu, so the two read apart.
        private static let gap: CGFloat = 8

        /// How far above the point given to `popUp` AppKit lays the menu's top:
        /// the padding over its first item.
        private static let menuInset: CGFloat = 5
    }
}

/// `NSMenuItem`'s target is weak, so the action lives on the item itself.
private final class MenuAction: NSObject {
    let perform: () -> Void

    init(_ perform: @escaping () -> Void) { self.perform = perform }

    @objc func fire(_ sender: Any?) { perform() }
}

private extension DockStacking {
    /// Add to Stack for an `NSMenu`: what `DockStackingMenu` is for SwiftUI's.
    var menuItem: NSMenuItem {
        let submenu = NSMenu(title: "Add to Stack")
        for stack in stacks { submenu.addItem(stack.stackMenuTitle) { add(stack.id) } }
        if !stacks.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem("New Stack") { add(nil) }
        let item = NSMenuItem(title: "Add to Stack", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: "")
        let target = MenuAction(action)
        item.target = target
        item.representedObject = target
        addItem(item)
        return item
    }
}

/// The red count the Dock puts on a tile: white text on red, tall enough to read
/// at the dock's size, wide enough for the text.
private struct NotificationBadge: View {
    let label: String

    @Environment(\.dockTileSize) private var size

    var body: some View {
        let height = max(14, size * 0.3)
        Text(label)
            .font(.system(size: height * 0.62, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, height * 0.3)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(Color(red: 1, green: 0.23, blue: 0.19)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: max(1, height * 0.08)))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .accessibilityLabel("\(label) notifications")
    }
}

/// Keeps `DockBadgeMonitor` reading the Dock while a dock that shows badges is up.
private struct BadgeSubscription: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { if active { DockBadgeMonitor.shared.retain() } }
            .onDisappear { if active { DockBadgeMonitor.shared.release() } }
            .onChange(of: active) { _, active in
                active ? DockBadgeMonitor.shared.retain() : DockBadgeMonitor.shared.release()
            }
    }
}

extension DockTile {
    var runningApp: NSRunningApplication? {
        guard let identifier = bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { !$0.isTerminated }
    }

    var url: URL? {
        guard let path else { return nil }
        return kind == .url ? URL(string: path) : URL(fileURLWithPath: path)
    }

    /// What a click on the tile does: opens the app — launching it, or bringing a
    /// running one forward — or opens the folder or link.
    ///
    /// A running app goes through `openApplication` too, as the Dock does, rather
    /// than `activate()`: that only brings the app forward, and an app whose last
    /// window was closed — Claude, WhatsApp — comes forward with nothing to show.
    /// Opening it again sends the reopen event that makes it put a window back.
    func open() {
        guard let url else { return }
        if kind == .app {
            runningApp?.unhide()
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Widgets

/// One widget. The simple ones sit on a single card; the agents widget lays out a
/// card per session. In a column every card is a tile the size of an app icon and
/// the content re-flows to fit, so the widgets never widen the dock.
struct WidgetTileView: View {
    let tile: WidgetTile

    @Environment(\.dockVertical) private var vertical

    var body: some View {
        Group {
            switch tile.kind {
            // Widgets with no menu of their own still get Remove and Settings.
            case .clock: ClockWidget().widgetCard(square: vertical).dockContextMenu {}
            case .date: DateWidget().widgetCard(square: vertical).dockContextMenu {}
            case .battery: BatteryWidget().widgetCard(square: vertical).dockContextMenu {}
            case .accessories: AccessoriesWidget(tile: tile).dockContextMenu {}
            case .agents: AgentsWidget(tile: tile).dockContextMenu {}
            case .appStack: AppStackWidget(tile: tile).dockContextMenu {}
            case .launcher: LauncherWidget(tile: tile)
            case .nowPlaying: NowPlayingWidget(tile: tile)
            case .profiles: ProfilesWidget(tile: tile)
            case .trash: TrashWidget(tile: tile)
            case .airDrop: AirDropWidget(tile: tile)
            case .folderStack: FolderStackWidget(tile: tile)
            case .aiUsage: AIUsageWidget(tile: tile)
            }
        }
        .foregroundStyle(DockPalette.onSlab)
        .environment(\.dockWidget, tile)
    }
}

/// The card behind a widget: as tall as an app tile, and in a column as wide as
/// the dock, so the cards line up edge to edge like the Dock's own tiles.
struct WidgetCard: ViewModifier {
    /// A tile the size of an app icon, rather than a card that grows with its content.
    var square = false
    /// Taller than a tile, for a square card with more than one row in it.
    var height: CGFloat?

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @Environment(\.dockTileCards) private var cards

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, square ? 4 : size * 0.18)
            .frame(width: square ? size : nil)
            .frame(minWidth: size, maxWidth: vertical && !square ? .infinity : nil)
            .frame(height: height ?? size)
            // Rigid along the row: when magnified neighbours make the row wider than
            // the panel proposes, the row overflows as a whole rather than squeezing
            // the cards until their content spills out.
            .fixedSize(horizontal: !vertical && !square, vertical: false)
            // Without cards the widget keeps its footprint, so nothing shifts.
            .background(
                RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                    .fill(DockPalette.onSlab.opacity(cards ? 0.10 : 0))
            )
    }
}

extension View {
    func widgetCard(square: Bool = false, height: CGFloat? = nil) -> some View {
        modifier(WidgetCard(square: square, height: height))
    }
}

/// Type sizes are given for the default 56pt tile and scale with it.
extension EnvironmentValues {
    func scaled(_ points: CGFloat) -> CGFloat { points * dockTileSize / 56 }
}

private struct ClockWidget: View {
    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                // A smaller face in a square tile, so "11:59" fits inside an icon's width.
                .font(.system(size: environment.scaled(vertical ? 15 : 20), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dockTooltip(
                    context.date.formatted(date: .omitted, time: .shortened),
                    context.date.formatted(date: .complete, time: .omitted)
                )
        }
    }
}

private struct DateWidget: View {
    @Environment(\.self) private var environment

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                Text(context.date, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: environment.scaled(10), weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.red)
                Text(context.date, format: .dateTime.day())
                    .font(.system(size: environment.scaled(22), weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .dockTooltip(context.date.formatted(date: .complete, time: .omitted))
        }
    }
}

private struct BatteryWidget: View {
    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = BatteryMonitor.shared

    var body: some View {
        if let status = monitor.status {
            // Side by side on a chip; with no room across, the percentage moves down.
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 5))
            layout {
                Image(systemName: symbolName(for: status))
                    .font(.system(size: environment.scaled(vertical ? 16 : 18)))
                    .foregroundStyle(tint(for: status))
                Text("\(status.level)%")
                    .font(.system(size: environment.scaled(vertical ? 11 : 14), weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .dockTooltip(
                "Battery \(status.level)%",
                status.isCharging ? "Charging" : (status.isOnACPower ? "On power, not charging" : "On battery")
            )
        } else {
            VStack(spacing: 2) {
                Image(systemName: "powerplug")
                    .font(.system(size: environment.scaled(18)))
                Text("Power")
                    .font(.system(size: environment.scaled(10), weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .dockTooltip("On power", "This Mac has no battery")
        }
    }

    private func symbolName(for status: BatteryStatus) -> String {
        let bucket: Int
        switch status.level {
        case ..<13: bucket = 0
        case ..<38: bucket = 25
        case ..<63: bucket = 50
        case ..<88: bucket = 75
        default: bucket = 100
        }
        return "battery.\(bucket)percent" + (status.isCharging ? ".bolt" : "")
    }

    private func tint(for status: BatteryStatus) -> Color {
        if status.isCharging { return .green }
        if status.level <= 20 { return .red }
        return DockPalette.onSlab
    }
}

// MARK: - Agents

/// The coding agents Agent Frame is tracking: a card per session, each a button
/// that brings the editor window hosting it forward — beyond a few, the rest fold
/// into a menu so the dock does not run away — or, folded into one tile, a count
/// that opens into the list, with or without the words.
private struct AgentsWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = AgentSessionMonitor.shared

    private let shown = 4

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            switch tile.agentsLayout {
            case .one:
                AgentsStackTile(tile: tile)
            case .minimal:
                AgentsStackTile(tile: tile, minimal: true)
            case .each:
                if monitor.sessions.isEmpty {
                    SessionChip(session: nil)
                } else {
                    ForEach(monitor.sessions.prefix(shown)) { session in
                        SessionChip(session: session)
                    }
                    if monitor.sessions.count > shown {
                        overflow
                    }
                }
            }
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    private var overflow: some View {
        Menu {
            ForEach(monitor.sessions.dropFirst(shown)) { session in
                Button {
                    AgentSessionMonitor.reveal(session)
                } label: {
                    Text("\(session.folderName) — \(session.state.title)")
                }
            }
        } label: {
            Text("+\(monitor.sessions.count - shown)")
                .font(.system(size: size * 0.25, weight: .semibold, design: .rounded))
                .frame(minWidth: size * 0.5)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .widgetCard(square: vertical)
    }
}

/// One session, or the empty state. In a row: dot, folder and what it is doing on
/// a chip. In a column: a tile the size of an app icon — dot above, name below —
/// so the sessions do not set the width of the whole dock.
private struct SessionChip: View {
    let session: AgentSession?

    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @State private var hovering = false

    private var stateColor: Color {
        session.map { Color(nsColor: $0.state.color) } ?? DockPalette.onSlab.opacity(0.6)
    }

    var body: some View {
        Button {
            guard let session else { return }
            DockTooltipController.shared.cancel()
            AgentSessionMonitor.reveal(session)
        } label: {
            Group {
                if vertical { tile } else { chip }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
        .widgetCard(square: vertical)
        .overlay(
            RoundedRectangle(cornerRadius: environment.dockTileSize * 0.21, style: .continuous)
                .fill(DockPalette.onSlab.opacity(hovering && session != nil ? 0.08 : 0))
                .allowsHitTesting(false)
        )
        .onHover { hovering = $0 }
        .dockTooltip(
            session.map { "\($0.folderName) — \($0.state.title)" } ?? "No agents",
            session.map { "\(($0.cwd as NSString).abbreviatingWithTildeInPath) · click to open" }
                ?? "Sessions tracked by Agent Frame appear here"
        )
    }

    private var chip: some View {
        HStack(spacing: environment.scaled(8)) {
            StatusDot(state: session?.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(session?.folderName ?? "No agents")
                    .font(.system(size: environment.scaled(13), weight: .semibold))
                    .lineLimit(1)
                Text(session?.state.title ?? "Agent Frame")
                    .font(.system(size: environment.scaled(10), weight: .medium))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
            }
            // Natural width, so a full row does not squeeze the name; long ones truncate.
            .frame(maxWidth: environment.scaled(180), alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tile: some View {
        VStack(spacing: environment.scaled(3)) {
            StatusDot(state: session?.state)
            Text(session?.folderName ?? "Agents")
                .font(.system(size: environment.scaled(9), weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(session == nil ? DockPalette.onSlab.opacity(0.6) : DockPalette.onSlab)
        }
    }
}

/// Agent Frame's colour for the state, pulsing while an agent is working.
struct StatusDot: View {
    let state: AgentState?

    @Environment(\.self) private var environment
    @State private var pulsing = false

    var body: some View {
        let color = state.map { Color(nsColor: $0.color) } ?? DockPalette.onSlab.opacity(0.3)
        let ring = environment.scaled(18)
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: ring, height: ring)
                .scaleEffect(pulsing ? 1 : 0.6)
                .opacity(state == .busy ? (pulsing ? 0 : 1) : 0)
            Circle()
                .fill(color)
                .frame(width: ring * 0.55, height: ring * 0.55)
        }
        .frame(width: ring, height: ring)
        .onAppear { startPulse() }
        .onChange(of: state) { startPulse() }
    }

    private func startPulse() {
        pulsing = false
        guard state == .busy else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            pulsing = true
        }
    }
}

// MARK: - Material

/// The slab behind the dock, and behind what opens off it — its tips and its
/// stacks — so they all read as one: blurred, glass or solid, with the profile's
/// colour washed over it if asked, and a hairline rim — except on glass, which
/// draws its own edge. A transparent dock's tips and stacks take the system slab,
/// since they need one of their own.
struct DockSlab: View {
    let look: DockLook
    let tint: Color?
    let cornerRadius: CGFloat

    @ObservedObject private var accessibility = AccessibilityDisplay.shared

    private var style: DockStyle { look.style.hasPlate ? look.style : .system }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let glass = DockMaterial.drawsGlass(style)
        // Blur off means a solid slab — except for glass, which goes clear instead.
        let solid = accessibility.reducesTransparency || (!look.translucent && !glass)
        ZStack {
            if solid {
                shape.fill(DockPalette.solid)
            } else {
                // Glass and blur are different views; a new style makes a new one.
                DockMaterial(style: style, cornerRadius: cornerRadius, frosted: look.translucent)
                    .id(style)
            }
            // Clear glass is the colour of whatever is behind it — white over a
            // white window, where white tiles vanish. It needs a dimming layer, as
            // Apple advises, so the tiles read over anything.
            if glass, !solid, !look.translucent {
                shape.fill(DockPalette.glassDim)
            }
            if look.tinted, let tint {
                shape.fill(tint.opacity(0.28))
            }
            shape.strokeBorder(DockPalette.rim, lineWidth: glass && !solid ? 0 : 1)
        }
    }
}

/// The blur behind the dock. A SwiftUI material would do inside a normal window,
/// but in a clear, borderless panel the blur has to come from AppKit: a visual
/// effect view for the glass styles, or Liquid Glass itself on Tahoe. The view
/// carries the style's appearance, so a light dock stays light in Dark Mode.
struct DockMaterial: NSViewRepresentable {
    var style: DockStyle = .system
    let cornerRadius: CGFloat
    /// Frosted glass blurs what is behind it; clear glass only refracts it. The
    /// blur styles ignore this — turning blur off makes them solid, not clear.
    var frosted = true

    /// Whether the style is drawn as Liquid Glass on this Mac.
    static func drawsGlass(_ style: DockStyle) -> Bool {
        style == .liquidGlass && DockStyle.supportsLiquidGlass
    }

    func makeNSView(context: Context) -> NSView {
        let view: NSView
        #if compiler(>=6.2)
        if #available(macOS 26, *), style == .liquidGlass {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = frosted ? .regular : .clear
            view = glass
        } else {
            view = Self.effectView()
        }
        #else
        view = Self.effectView()
        #endif
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.appearance = style.forcedAppearance
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.appearance = style.forcedAppearance
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.style = frosted ? .regular : .clear
        }
        #endif
    }

    private static func effectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
}

/// macOS's Reduce transparency setting, so a blurred dock goes solid with the rest
/// of the system — and comes back when it is turned off again.
@MainActor
final class AccessibilityDisplay: ObservableObject {
    static let shared = AccessibilityDisplay()

    @Published private(set) var reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    private var token: NSObjectProtocol?

    private init() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }
}
