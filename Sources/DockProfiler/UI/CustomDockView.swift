import AppKit
import SwiftUI

// MARK: - Environment

/// The height of an app icon or widget card, and whether the dock is a column.
/// Set once on the dock; every tile and widget draws itself to fit.
private struct DockTileSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 56
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

    var dockWidget: WidgetTile? {
        get { self[DockWidgetKey.self] }
        set { self[DockWidgetKey.self] = newValue }
    }

    var dockWidgetUpdate: ((WidgetTile) -> Void)? {
        get { self[DockWidgetUpdateKey.self] }
        set { self[DockWidgetUpdateKey.self] = newValue }
    }
}

// MARK: - Context menus

/// A tile's context menu in the dock: its own items; for a widget with settings,
/// those, right there in the menu; then Remove from Dock for one that is in the
/// profile and, on the live dock, a way to the dock's settings, under a divider.
/// A tile with nothing of its own still gets those, so a right-click anywhere on
/// the dock finds them.
private struct DockContextMenu<Items: View>: ViewModifier {
    let items: Items

    @Environment(\.dockSettingsAction) private var openSettings
    @Environment(\.dockRemoveAction) private var remove
    @Environment(\.dockWidget) private var widget
    @Environment(\.dockWidgetUpdate) private var update

    private var hasSettings: Bool { widget?.kind.isConfigurable == true && update != nil }

    func body(content: Content) -> some View {
        content.contextMenu {
            items
            if hasSettings, Items.self != EmptyView.self { Divider() }
            if hasSettings, let widget, let update {
                WidgetSettingsMenu(tile: widget, update: update)
            }
            if remove != nil || openSettings != nil, hasSettings || Items.self != EmptyView.self { Divider() }
            if let remove { Button("Remove from Dock", action: remove) }
            if let openSettings { Button("Custom Dock Settings…", action: openSettings) }
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
            if !tile.apps.isEmpty {
                Menu("Remove App") {
                    ForEach(tile.apps) { app in
                        Button(app.label) { edit { $0.apps.removeAll { $0.id == app.id } } }
                    }
                }
            }
        case .agents:
            Toggle("One Tile That Opens Into the Sessions", isOn: binding(\.stacked))
        case .nowPlaying:
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
                tile.apps.append(app)
            }
        }
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
    var tileSize: CGFloat = 56
    /// How much a tile under the pointer grows, in points; zero for no magnification.
    var magnificationExtra: CGFloat = 0
    var look = DockLook()
    /// The profile's colour, washed over the slab when the look asks for it.
    var tint: Color? = nil
    /// Called with the new order when an item is dragged to a new place, as the
    /// Dock's own tiles can be. Without it the items stay put.
    var onReorder: (([DockStripItem]) -> Void)? = nil

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
    /// The dock's frame in the hosting view, to place mouse events from `dragMonitor`.
    @State private var frameInHost: CGRect = .zero
    /// Follows the mouse once a drag has begun. The gesture alone stops at the
    /// panel's edge, and a removal takes the pointer well past it.
    @State private var dragMonitor: Any?
    /// The divider's slot, so a running app dropped before it is pinned.
    private static let dividerID = UUID()

    @Environment(\.colorScheme) private var systemColorScheme
    /// Set on the live dock only; the editor's preview has none.
    @Environment(\.dockSettingsAction) private var settingsAction
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
        let spacing = padding
        let layout = vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(displayedItems) { item in
                reorderable(item)
            }
            if showsRunningApps {
                // A running app being dragged takes a slot in the row as well, but its
                // view here must live on: the gesture is attached to it.
                let unpinned = running.unpinnedTiles(excluding: items.compactMap(\.tile))
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
        .padding(padding)
        .background(plate)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .modifier(SlabContextMenu())
        .overlay(ghost)
        // A forced light or dark style colours the tiles and cards too, not just the
        // slab. The panel sets the same appearance on its window; this covers the
        // preview in the editor, whose window keeps the system's.
        .environment(\.colorScheme, style.forcedColorScheme ?? systemColorScheme)
        .environment(\.dockTileCards, look.drawsTileCards)
        .environment(\.dockShowsBadges, showsBadges)
        .modifier(BadgeSubscription(active: showsBadges))
        .coordinateSpace(name: "dock")
        .onContinuousHover(coordinateSpace: .named("dock")) { phase in
            guard magnificationExtra > 0, dragging == nil else { return }
            switch phase {
            case .active(let point): pointer = vertical ? point.y : point.x
            case .ended: pointer = nil
            }
        }
        .onPreferenceChange(TileFrameKey.self) { frames = $0 }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: HostFrameKey.self, value: geometry.frame(in: .global))
        })
        .onPreferenceChange(HostFrameKey.self) { frameInHost = $0 }
        .onChange(of: items) { pendingOrder = nil }
        .environment(\.dockTileSize, tileSize)
        .environment(\.dockVertical, vertical)
        .environment(\.dockEdge, edge)
    }

    /// The slab behind the tiles: blurred, glass or solid, with the profile's colour
    /// washed over it if asked, and a hairline rim — except on glass, which draws its
    /// own edge. Nothing at all when the look is transparent.
    @ViewBuilder
    private var plate: some View {
        if style.hasPlate {
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
                        if removing {
                            Text("Remove")
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
        shuffle(item.id)
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
        if let order = pendingOrder, order.map(\.id) != items.map(\.id) {
            onReorder?(order)
            // The new items arrive through the profile; if for any reason they do
            // not, the dock goes back to what it was given.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if dragging == nil { pendingOrder = nil }
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
/// settings item, and only on the live dock.
private struct SlabContextMenu: ViewModifier {
    @Environment(\.dockSettingsAction) private var openSettings

    func body(content: Content) -> some View {
        if let openSettings {
            content.contextMenu {
                Button("Custom Dock Settings…", action: openSettings)
            }
        } else {
            content
        }
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

private struct HostFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
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
    private let reach: CGFloat = 2.5

    private var scale: CGFloat {
        guard extra > 0, let pointer, let center = centers[id] else { return 1 }
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
        .dockContextMenu { menu }
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

    private var runningApp: NSRunningApplication? { tile.runningApp }
    private var url: URL? { tile.url }

    private func open() {
        DockTooltipController.shared.cancel()
        tile.open()
    }

    @ViewBuilder
    private var menu: some View {
        if let app = runningApp {
            Button(app.isHidden ? "Show" : "Hide") { _ = app.isHidden ? app.unhide() : app.hide() }
            Button("Quit") { app.terminate() }
            Divider()
        }
        if let url, url.isFileURL {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
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
/// that brings the editor window hosting it forward. Beyond a few, the rest fold
/// into a menu so the dock does not run away.
private struct AgentsWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = AgentSessionMonitor.shared

    private let shown = 4

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if tile.stacked {
                AgentsStackTile(tile: tile)
            } else if monitor.sessions.isEmpty {
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
