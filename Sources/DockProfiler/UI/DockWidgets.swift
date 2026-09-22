import AppKit
import SwiftUI

// MARK: - Shared pieces

/// A widget drawn as an icon the size of an app tile — a folder, an app stack, the
/// Trash — with the same hover lift as the apps beside it. No card: these stand in
/// for Dock tiles, so they look like Dock tiles.
private struct IconTile<Icon: View>: View {
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.dockTileSize) private var size
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: size - 8, height: size - 8)
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A widget on a card that lights up under the pointer: a chip in a row, a square
/// tile in a column, like the agents' session chips.
private struct CardButton<Content: View>: View {
    let action: () -> Void
    /// A square tile whichever way the dock runs; nil follows the dock.
    var square: Bool? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .widgetCard(square: square ?? vertical)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                .fill(DockPalette.onSlab.opacity(hovering ? 0.08 : 0))
                .allowsHitTesting(false)
        )
        .onHover { hovering = $0 }
    }
}

/// A small count on the corner of a tile, in the colour of whatever is most urgent.
private struct CountBadge: View {
    let count: Int
    let color: Color

    @Environment(\.self) private var environment

    var body: some View {
        Text("\(count)")
            .font(.system(size: environment.scaled(9), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, environment.scaled(4))
            .frame(minWidth: environment.scaled(15), minHeight: environment.scaled(15))
            .background(Capsule().fill(color))
    }
}

// MARK: - Folder stack

/// A folder that opens into its most recent files, like a Dock stack.
struct FolderStackWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockEdge) private var edge

    private var url: URL? { tile.path.map { URL(fileURLWithPath: $0, isDirectory: true) } }
    private var exists: Bool { tile.path.map { FileManager.default.fileExists(atPath: $0) } ?? false }

    var body: some View {
        IconTile(action: open) {
            if let path = tile.path, exists {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(DockPalette.onSlab.opacity(0.12))
                    .overlay(
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                    )
            }
        }
        .dockTooltip(tile.title, exists ? "Click for recent files" : "Folder not found")
        .dockContextMenu {
            if let url, exists {
                Button("Open in Finder") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func open() {
        DockTooltipController.shared.cancel()
        guard let url, exists else { return }
        DockStackController.shared.toggle(
            for: tile.id,
            content: DockStackContent(
                title: tile.title,
                items: Self.items(in: url),
                style: .grid,
                emptyText: "This folder is empty",
                footer: DockStackItem(
                    id: "finder",
                    title: "Open in Finder",
                    icon: .symbol("folder", DockPalette.onSlab),
                    action: { NSWorkspace.shared.open(url) }
                )
            ),
            edge: edge
        )
    }

    /// The folder's contents, newest first, as the Dock's "date added" stacks show them.
    private static func items(in folder: URL) -> [DockStackItem] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .localizedNameKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        func date(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
        }
        return contents
            .sorted { date($0) > date($1) }
            .prefix(40)
            .map { url in
                DockStackItem(
                    id: url.path,
                    title: (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent,
                    subtitle: url.lastPathComponent,
                    icon: .image(NSWorkspace.shared.icon(forFile: url.path)),
                    action: { NSWorkspace.shared.open(url) }
                )
            }
    }
}

// MARK: - App stack

/// Several apps folded into one tile — a grid of their icons — that opens into the
/// apps themselves.
struct AppStackWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockStackTargeted) private var targeted
    @Environment(\.dockWidgetUpdate) private var update
    @Environment(\.dockStackMoveOut) private var moveOut
    @ObservedObject private var running = RunningAppsMonitor.shared
    @ObservedObject private var profiles = BrowserProfileMonitor.shared

    var body: some View {
        IconTile(action: open) {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(DockPalette.onSlab.opacity(targeted ? 0.3 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0)
                )
                .overlay(preview.padding(size * 0.1))
                // A held tile over it: the stack opens up to take it.
                .scaleEffect(targeted ? 1.15 : 1)
                .animation(.easeOut(duration: 0.15), value: targeted)
        }
        .dockTooltip(
            tile.stack.isEmpty ? "App Stack" : "\(tile.stack.count) app\(tile.stack.count == 1 ? "" : "s")",
            tile.stack.isEmpty ? "Add apps in the profile editor" : tile.stack.prefix(4).map(\.title).joined(separator: ", ")
        )
    }

    /// Up to four icons in a two-by-two grid; fewer sit centred.
    @ViewBuilder
    private var preview: some View {
        let shown = Array(tile.stack.prefix(4))
        if shown.isEmpty {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: size * 0.36))
                .foregroundStyle(DockPalette.onSlab.opacity(0.7))
        } else {
            let columns = shown.count == 1 ? 1 : 2
            let spacing: CGFloat = 2
            let side = (size * 0.8 - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(shown) { entry in
                    if let image = entry.image {
                        BadgedIcon(image: image, badge: entry.badge(side: side), side: side)
                    } else {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                            .frame(width: side, height: side)
                    }
                }
            }
        }
    }

    private func open() {
        DockTooltipController.shared.cancel()
        let items = tile.stack.map { entry in
            DockStackItem(
                id: entry.id.uuidString,
                title: entry.title,
                subtitle: entry.subtitle,
                icon: entry.image.map { .image($0, badge: entry.badge(side: 44)) } ?? .symbol("app.dashed", DockPalette.onSlab),
                isCurrent: entry.isRunning(among: running.bundleIdentifiers, profiles: profiles),
                action: { entry.open() },
                menu: menu(for: entry)
            )
        }
        // On the live dock the stack's order and contents are its own to change;
        // in the editor's preview they are set on the card.
        let editable = update != nil
        DockStackController.shared.toggle(
            for: tile.id,
            content: DockStackContent(
                title: tile.stack.isEmpty ? "App Stack" : "\(tile.stack.count) apps",
                items: items,
                style: .grid,
                emptyText: "Add apps to this stack in the profile editor",
                onReorder: editable ? { ids in
                    edit { stack in stack.stack = ids.compactMap { id in stack.stack.first { $0.id.uuidString == id } } }
                } : nil,
                onMoveOut: editable && moveOut != nil ? { id in
                    if let entry = tile.stack.first(where: { $0.id.uuidString == id }) { moveOut?(entry, tile.id) }
                } : nil
            ),
            edge: edge
        )
    }

    /// The entry's own menu: open it, show it in Finder, make a launcher of an app,
    /// take it out of the stack, or drop it from the stack — the last three on the
    /// live dock alone.
    private func menu(for entry: AppStackEntry) -> [DockStackMenuEntry] {
        var menu: [DockStackMenuEntry] = [.item("Open") { entry.open() }]
        if let path = entry.path, !entry.isMissing {
            menu.append(.item("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) })
        }
        guard update != nil else { return menu }
        menu.append(.separator)
        if entry.app != nil {
            menu.append(.item("Make a Launcher") { edit { $0.makeLauncher(of: entry.id) } })
        }
        if let moveOut {
            menu.append(.item("Move Out of Stack") { moveOut(entry, tile.id) })
        }
        menu.append(.separator)
        menu.append(.item("Remove from Stack", destructive: true) { edit { $0.stack.removeAll { $0.id == entry.id } } })
        return menu
    }

    private func edit(_ change: (inout WidgetTile) -> Void) {
        var changed = tile
        change(&changed)
        update?(changed)
    }
}

extension AppStackEntry {
    /// The app's icon, or the launcher's own — or its app's, to take the badge;
    /// nil when the app has gone.
    var image: NSImage? {
        switch self {
        case .app(let app): return app.icon
        case .launcher(let launcher): return Launcher.customIcon(of: launcher) ?? Launcher.appIcon(of: launcher)
        }
    }

    /// The launcher's badge for the corner of an icon drawn `side` wide; none for
    /// an app, or a launcher with an icon of its own.
    func badge(side: CGFloat) -> NSImage? {
        guard case .launcher(let launcher) = self, Launcher.customIcon(of: launcher) == nil else { return nil }
        return Launcher.badgeImage(of: launcher, side: BadgedIcon.badgeSide(for: side))
    }

    /// The app's path, or what the launcher opens it with.
    var subtitle: String? {
        switch self {
        case .app(let app): return app.subtitle
        case .launcher(let launcher): return launcher.launchSummary
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .app(let app): return app.bundleIdentifier
        case .launcher(let launcher): return launcher.appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        }
    }

    /// Whether the entry is marked as running: an app by its process, a launcher
    /// by its profile where it has one.
    @MainActor func isRunning(among running: Set<String>, profiles: BrowserProfileMonitor) -> Bool {
        switch self {
        case .app(let app): return app.bundleIdentifier.map { running.contains($0) } ?? false
        case .launcher(let launcher): return profiles.isRunning(launcher, among: running)
        }
    }

    var isMissing: Bool {
        switch self {
        case .app(let app): return app.isMissing
        case .launcher(let launcher): return launcher.path.map { !FileManager.default.fileExists(atPath: $0) } ?? false
        }
    }

    @MainActor func open() {
        switch self {
        case .app(let app): app.open()
        case .launcher(let launcher): Launcher.open(launcher)
        }
    }
}

extension WidgetTile {
    /// Launcher: the profile and the arguments in a line, for a tooltip or a
    /// stack's subtitle; nil with neither.
    var launchSummary: String? {
        var parts: [String] = []
        if let profile = browserProfile { parts.append("As \(profile.name)") }
        let arguments = arguments.trimmingCharacters(in: .whitespaces)
        if !arguments.isEmpty { parts.append(arguments) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Launcher

/// An app opened with arguments of its own — a browser as one of its profiles, an
/// editor on a folder — drawn as an app tile: its icon with the running dot under
/// it, and the profile's picture badged on the corner so two tiles of the same
/// browser are told apart. An icon of its own replaces the app's altogether.
/// The dot goes by the profile where there is one, so each profile's tile shows
/// its own state, as a Windows taskbar does.
struct LauncherWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var running = RunningAppsMonitor.shared
    @ObservedObject private var profiles = BrowserProfileMonitor.shared
    @State private var hovering = false

    /// For a browser opened as one of its profiles, the dot is that profile's own:
    /// lit while it has a window up, dark while only the others do.
    private var isRunning: Bool { profiles.isRunning(tile, among: running.bundleIdentifiers) }
    private var isMissing: Bool { tile.path.map { !FileManager.default.fileExists(atPath: $0) } ?? false }

    var body: some View {
        let dotRoom: CGFloat = 8
        let layout = vertical ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        Button(action: open) {
            layout {
                icon
                    .frame(width: size - dotRoom, height: size - dotRoom)
                    .scaleEffect(hovering ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                Circle()
                    .fill(DockPalette.onSlab.opacity(isRunning ? 0.85 : 0))
                    .frame(width: 4, height: 4)
                    .frame(width: vertical ? dotRoom : nil, height: vertical ? nil : dotRoom)
            }
            .frame(width: vertical ? size : nil, height: vertical ? nil : size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dockTooltip(tile.title, subtitle)
        .dockContextMenu {
            if let url = tile.appURL, !isMissing {
                Button("Open") { open() }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let custom = Launcher.customIcon(of: tile) {
            Image(nsImage: custom).resizable().aspectRatio(contentMode: .fit)
        } else if let app = Launcher.appIcon(of: tile) {
            let side = size - 8
            BadgedIcon(image: app, badge: Launcher.badgeImage(of: tile, side: BadgedIcon.badgeSide(for: side)), side: side)
        } else {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(DockPalette.onSlab.opacity(0.12))
                .overlay(
                    Image(systemName: tile.path == nil ? "arrow.up.forward.app" : "questionmark")
                        .font(.system(size: size * 0.36))
                        .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                )
        }
    }

    private var subtitle: String? {
        guard tile.path != nil else { return "Choose an app in the profile editor" }
        if isMissing { return "Moved or deleted" }
        return tile.launchSummary
    }

    private func open() {
        DockTooltipController.shared.cancel()
        Launcher.open(tile)
    }
}

/// An icon with a launcher's badge on its corner — the profile's picture, or its
/// letters — clipped to a disc and ringed so it stands off the icon, the way a
/// Dock badge does. The ring is the slab's colour, for the dock and the panels
/// drawn on it; the editor passes its own window's.
struct BadgedIcon: View {
    let image: NSImage
    let badge: NSImage?
    let side: CGFloat
    var ring: Color = DockPalette.slab

    /// The badge's width on an icon `side` wide.
    static func badgeSide(for side: CGFloat) -> CGFloat { side * 0.42 }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: side, height: side)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    let badgeSide = Self.badgeSide(for: side)
                    Image(nsImage: badge)
                        .resizable()
                        .frame(width: badgeSide, height: badgeSide)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(ring, lineWidth: max(1.5, badgeSide * 0.08)))
                        .offset(x: badgeSide * 0.12, y: badgeSide * 0.12)
                }
            }
    }
}

// MARK: - Agents, stacked

/// The agents widget folded into one tile: a count in the colour of the most urgent
/// session, opening into the list. Minimal drops the words and keeps the icon and
/// the count on a square tile, whichever way the dock runs. `AgentsWidget` keeps
/// the monitor running.
struct AgentsStackTile: View {
    let tile: WidgetTile
    var minimal: Bool = false

    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @Environment(\.dockEdge) private var edge
    @ObservedObject private var monitor = AgentSessionMonitor.shared

    /// Sessions come most urgent first.
    private var urgent: AgentState? { monitor.sessions.first?.state }

    /// The icon stands alone on a square tile: in a column, and when minimal.
    private var compact: Bool { vertical || minimal }

    var body: some View {
        CardButton(action: open, square: minimal ? true : nil) {
            let layout = compact ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: environment.scaled(8)))
            layout {
                BotGlyph()
                    .frame(width: environment.scaled(compact ? 20 : 24), height: environment.scaled(compact ? 20 : 24))
                    .foregroundStyle(monitor.sessions.isEmpty ? DockPalette.onSlab.opacity(0.5) : DockPalette.onSlab)
                    .overlay(alignment: .topTrailing) {
                        if !monitor.sessions.isEmpty {
                            CountBadge(count: monitor.sessions.count, color: Color(nsColor: (urgent ?? .idle).color))
                                .offset(x: environment.scaled(8), y: -environment.scaled(6))
                        }
                    }
                if !compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Agents")
                            .font(.system(size: environment.scaled(13), weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: environment.scaled(10), weight: .medium))
                            .foregroundStyle(urgent.map { Color(nsColor: $0.color) } ?? DockPalette.onSlab.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
        }
        .dockTooltip("Agents", tooltipDetail)
    }

    private var tooltipDetail: String {
        switch monitor.sessions.count {
        case 0: return "Sessions tracked by Agent Frame appear here"
        case 1: return "\(monitor.sessions[0].folderName) — \(subtitle) · click to open"
        default: return "\(subtitle) · click for the list"
        }
    }

    private var subtitle: String {
        let sessions = monitor.sessions
        guard !sessions.isEmpty else { return "None running" }
        let waiting = sessions.filter { $0.state == .waiting }.count
        let busy = sessions.filter { $0.state == .busy }.count
        if waiting > 0 { return "\(waiting) waiting" }
        if busy > 0 { return "\(busy) working" }
        return "\(sessions.count) idle"
    }

    private func open() {
        DockTooltipController.shared.cancel()
        // One session needs no list: go straight to it.
        if monitor.sessions.count == 1 {
            AgentSessionMonitor.reveal(monitor.sessions[0])
            return
        }
        let items = monitor.sessions.map { session in
            DockStackItem(
                id: session.id,
                title: session.folderName,
                subtitle: "\(session.state.title) · \((session.cwd as NSString).abbreviatingWithTildeInPath)",
                icon: .dot(Color(nsColor: session.state.color)),
                action: { AgentSessionMonitor.reveal(session) }
            )
        }
        DockStackController.shared.toggle(
            for: tile.id,
            content: DockStackContent(
                title: "Agents",
                items: items,
                style: .list,
                emptyText: "No agents running"
            ),
            edge: edge
        )
    }
}

// MARK: - Accessories

/// The batteries of the wireless accessories on this Mac — AirPods and their
/// case, a Magic Keyboard, a mouse — and the Mac's own if wanted: a tile the size
/// of an app icon per device, its icon inside a ring that empties with it, as
/// the Batteries widget in Notification Centre draws them. Beyond a few, the rest
/// fold into a menu so the dock does not run away.
struct AccessoriesWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = AccessoryBatteryMonitor.shared
    @ObservedObject private var macBattery = BatteryMonitor.shared

    private let shown = 5

    /// What the tile is set to show: this Mac first, then every accessory not ticked off.
    private var devices: [AccessoryBattery] {
        var devices = monitor.devices.filter { !tile.hiddenAccessoryIDs.contains($0.id) }
        if tile.showsMacBattery, let status = macBattery.status {
            devices.insert(.mac(status), at: 0)
        }
        return devices
    }

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if devices.isEmpty {
                AccessoryTile(device: nil, showsLevel: tile.accessoryLayout == .ring)
            } else {
                ForEach(devices.prefix(shown)) { device in
                    AccessoryTile(device: device, showsLevel: tile.accessoryLayout == .ring)
                }
                if devices.count > shown {
                    overflow
                }
            }
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    private var overflow: some View {
        Menu {
            ForEach(devices.dropFirst(shown)) { device in
                Button {
                    AccessoryBatteryMonitor.openBluetoothSettings()
                } label: {
                    Text("\(device.name) — \(device.detail)")
                }
            }
        } label: {
            Text("+\(devices.count - shown)")
                .font(.system(size: size * 0.25, weight: .semibold, design: .rounded))
                .frame(minWidth: size * 0.5)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .widgetCard(square: true)
    }
}

/// A device's icon inside a ring filled to its level, the way macOS draws its
/// batteries: green, red when about to run out, a bolt on the ring while it
/// charges; dimmed for the empty state.
private struct BatteryRing: View {
    let device: AccessoryBattery?
    /// The ring's diameter.
    let diameter: CGFloat

    private var color: Color {
        guard let device else { return DockPalette.onSlab.opacity(0.35) }
        return device.level <= 20 && !device.isCharging ? .red : .green
    }

    var body: some View {
        let lineWidth = LevelRing.lineWidth(for: diameter)
        ZStack {
            LevelRing(fraction: device.map { Double($0.level) / 100 } ?? 0, color: color, lineWidth: lineWidth)
            Image(systemName: device?.kind.symbolName ?? AccessoryBattery.Kind.headphones.symbolName)
                .font(.system(size: diameter * 0.4, weight: .medium))
                .foregroundStyle(device == nil ? DockPalette.onSlab.opacity(0.5) : DockPalette.onSlab)
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topLeading) {
            if device?.isCharging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: diameter * 0.28, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(lineWidth * 0.5)
                    .background(Circle().fill(DockPalette.slab))
                    .offset(x: -lineWidth * 0.6, y: -lineWidth * 0.6)
            }
        }
    }
}

/// The level under a ring.
private struct LevelLabel: View {
    let device: AccessoryBattery?

    @Environment(\.self) private var environment

    var body: some View {
        Text(device.map { "\($0.level)%" } ?? "None")
            .font(.system(size: environment.scaled(9), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
    }

    private var color: Color {
        guard let device else { return DockPalette.onSlab.opacity(0.6) }
        return device.level <= 20 && !device.isCharging ? .red : DockPalette.onSlab.opacity(0.85)
    }
}

/// One device, or the empty state: a square tile with its ring, and its level
/// under it if asked for. Clicking opens Bluetooth settings, where the
/// accessories are.
private struct AccessoryTile: View {
    let device: AccessoryBattery?
    let showsLevel: Bool

    @Environment(\.self) private var environment

    var body: some View {
        CardButton(action: open, square: true) {
            VStack(spacing: environment.scaled(2)) {
                BatteryRing(device: device, diameter: environment.scaled(showsLevel ? 28 : 32))
                if showsLevel {
                    LevelLabel(device: device)
                }
            }
        }
        .disabled(device == nil)
        .dockTooltip(
            device.map { "\($0.name) — \($0.detail)" } ?? "No accessories",
            device == nil ? "AirPods, keyboards, mice and headphones that report their charge appear here" : "Click for Bluetooth settings"
        )
    }

    private func open() {
        DockTooltipController.shared.cancel()
        AccessoryBatteryMonitor.openBluetoothSettings()
    }
}

// MARK: - Trash

/// The Trash, full or empty: click opens it, files dropped on it go in.
struct TrashWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @ObservedObject private var monitor = TrashMonitor.shared
    @State private var targeted = false

    var body: some View {
        IconTile(action: open) {
            Image(nsImage: NSImage(named: monitor.isFull ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSImage())
                .resizable()
                .scaleEffect(targeted ? 1.15 : 1)
                .animation(.easeOut(duration: 0.12), value: targeted)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let failed = monitor.trash(urls)
            return failed.count < urls.count
        } isTargeted: { targeted = $0 }
        .dockTooltip("Trash", subtitle)
        .dockContextMenu {
            Button("Open Trash") { TrashMonitor.reveal() }
            Button("Empty Trash…") { monitor.emptyAfterConfirming() }
                .disabled(!monitor.isFull)
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    private var subtitle: String {
        guard let count = monitor.count else { return "Drop files here to delete them" }
        if count == 0 { return "Empty" }
        return "\(count) item\(count == 1 ? "" : "s") · drop files here to delete them"
    }

    private func open() {
        DockTooltipController.shared.cancel()
        TrashMonitor.reveal()
    }
}

// MARK: - AirDrop

/// AirDrop as a tile: drop files on it and the AirDrop picker opens with them, so
/// sending something to the phone is one drag. Click it for Finder's AirDrop window.
struct AirDropWidget: View {
    let tile: WidgetTile

    @Environment(\.dockTileSize) private var size
    @State private var targeted = false

    /// Finder's own AirDrop app: opening it brings up the AirDrop window.
    private static let airDropApp = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"

    var body: some View {
        // The mark on its own, on a card like the ring widgets beside it — Finder's
        // white app icon would sit oddly among the dock's own tiles.
        CardButton(action: open) {
            AirDropGlyph()
                .foregroundStyle(Color(nsColor: .systemBlue))
                .frame(width: size * 0.62, height: size * 0.62)
                .scaleEffect(targeted ? 1.15 : 1)
                .animation(.easeOut(duration: 0.12), value: targeted)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Self.send(urls)
        } isTargeted: { targeted = $0 }
        .dockTooltip("AirDrop", "Drop files here to send them to a nearby device")
        .dockContextMenu {
            Button("Open AirDrop") { Self.reveal() }
        }
    }

    private func open() {
        DockTooltipController.shared.cancel()
        Self.reveal()
    }

    private static func reveal() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: airDropApp), configuration: .init())
    }

    /// Hands the files to the AirDrop sharing service, which shows its picker of
    /// nearby devices. The picker is a window of ours, so the app comes forward for it.
    @discardableResult
    private static func send(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: files) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
        return true
    }
}

/// The AirDrop mark — a dot inside three arcs open at the bottom — drawn to fit its
/// frame in whatever foreground style is set, so it can be a blue tile in the
/// dock and a grey one in the editor. There is no SF Symbol for it.
struct AirDropGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = side * 0.08
            ZStack {
                Circle()
                    .fill(.foreground)
                    .frame(width: side * 0.14, height: side * 0.14)
                ForEach([0.42, 0.69, 0.96], id: \.self) { diameter in
                    Circle()
                        .trim(from: 0.12, to: 0.88)
                        .stroke(.foreground, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(90))
                        .frame(width: side * diameter - stroke, height: side * diameter - stroke)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// The glyph as a template image, for menus.
    @MainActor
    static let menuImage: NSImage? = templateImage(AirDropGlyph())
}

/// Lucide's `bot` (lucide.dev/icons/bot), for the agents: a head with an antenna,
/// two eyes and an ear either side, drawn on its 24-unit grid with a 2-unit round
/// stroke and scaled to fit, in whatever foreground style is set.
struct BotGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let unit = side / 24
            let stroke = StrokeStyle(lineWidth: 2 * unit, lineCap: .round, lineJoin: .round)
            ZStack {
                Path { path in
                    // Antenna: M12 8V4H8
                    path.move(to: CGPoint(x: 12, y: 8))
                    path.addLine(to: CGPoint(x: 12, y: 4))
                    path.addLine(to: CGPoint(x: 8, y: 4))
                    // Ears: M2 14h2, M20 14h2
                    path.move(to: CGPoint(x: 2, y: 14)); path.addLine(to: CGPoint(x: 4, y: 14))
                    path.move(to: CGPoint(x: 20, y: 14)); path.addLine(to: CGPoint(x: 22, y: 14))
                    // Eyes: M15 13v2, M9 13v2
                    path.move(to: CGPoint(x: 15, y: 13)); path.addLine(to: CGPoint(x: 15, y: 15))
                    path.move(to: CGPoint(x: 9, y: 13)); path.addLine(to: CGPoint(x: 9, y: 15))
                    // Head: rect 16×12 at (4, 8), rx 2
                    path.addRoundedRect(in: CGRect(x: 4, y: 8, width: 16, height: 12), cornerSize: CGSize(width: 2, height: 2))
                }
                .applying(CGAffineTransform(scaleX: unit, y: unit))
                .stroke(.foreground, style: stroke)
            }
            .frame(width: side, height: side)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// The glyph as a template image, for menus.
    @MainActor
    static let menuImage: NSImage? = templateImage(BotGlyph())
}

/// A view rendered as a 16 pt template image, for menus, which take images rather
/// than views.
@MainActor
func templateImage<Content: View>(_ content: Content) -> NSImage? {
    let renderer = ImageRenderer(content: content.foregroundStyle(.black).frame(width: 16, height: 16))
    renderer.scale = 2
    let image = renderer.nsImage
    image?.isTemplate = true
    return image
}

/// A widget kind's icon at a given size: its SF Symbol, or one of the marks drawn
/// here, for the kinds that have none.
struct WidgetKindIcon: View {
    let kind: WidgetKind
    var size: CGFloat = 13

    var body: some View {
        switch kind {
        case .airDrop: AirDropGlyph().frame(width: size * 1.05, height: size * 1.05)
        case .agents: BotGlyph().frame(width: size * 1.25, height: size * 1.25)
        default: Image(systemName: kind.symbolName).font(.system(size: size))
        }
    }

    /// The icon for a menu item, where only images will do.
    @MainActor
    static func menuImage(for kind: WidgetKind) -> NSImage? {
        switch kind {
        case .airDrop: return AirDropGlyph.menuImage
        case .agents: return BotGlyph.menuImage
        default: return nil
        }
    }
}

// MARK: - Profiles

/// The active profile, opening into the list of profiles to switch to.
struct ProfilesWidget: View {
    let tile: WidgetTile

    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @Environment(\.dockEdge) private var edge
    @ObservedObject private var store = ProfileStore.shared

    private var active: DockProfile? { store.activeProfile }

    var body: some View {
        CardButton(action: open) {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: environment.scaled(8)))
            layout {
                profileIcon(active, size: environment.scaled(vertical ? 24 : 30))
                if vertical {
                    Text(active?.name ?? "Profiles")
                        .font(.system(size: environment.scaled(9), weight: .semibold))
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active?.name ?? "No profile")
                            .font(.system(size: environment.scaled(13), weight: .semibold))
                            .lineLimit(1)
                        Text(store.isApplying ? "Switching…" : "Profile")
                            .font(.system(size: environment.scaled(10), weight: .medium))
                            .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                    }
                    .frame(maxWidth: environment.scaled(160), alignment: .leading)
                }
            }
            .fixedSize(horizontal: !vertical, vertical: false)
        }
        .dockTooltip(active?.name ?? "Profiles", "Click to switch profile")
        .dockContextMenu {
            Button("Manage Profiles…") { ManagerWindowController.shared.show(selecting: store.activeProfileID) }
        }
    }

    private func profileIcon(_ profile: DockProfile?, size: CGFloat) -> some View {
        let color = profile?.color.color ?? DockPalette.onSlab.opacity(0.5)
        return RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: profile?.symbol ?? "square.grid.2x2")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(color)
            )
    }

    private func open() {
        DockTooltipController.shared.cancel()
        let items = store.profiles.map { profile in
            DockStackItem(
                id: profile.id.uuidString,
                title: profile.name,
                subtitle: profile.itemSummary,
                icon: .symbol(profile.symbol, profile.color.color),
                isCurrent: profile.id == store.activeProfileID,
                action: { ProfileStore.shared.activate(profile.id) }
            )
        }
        DockStackController.shared.toggle(
            for: tile.id,
            content: DockStackContent(
                title: "Profiles",
                items: items,
                style: .list,
                emptyText: "No profiles yet",
                footer: DockStackItem(
                    id: "manage",
                    title: "Manage Profiles…",
                    icon: .symbol("slider.horizontal.3", DockPalette.onSlab),
                    action: { ManagerWindowController.shared.show(selecting: ProfileStore.shared.activeProfileID) }
                )
            ),
            edge: edge
        )
    }
}

// MARK: - Now playing

/// What Music or Spotify is playing: the album art — or the player's icon until it
/// arrives — with as much of the track beside it as the layout asks for. Click to
/// play or pause; skip from the context menu, or from the buttons when the widget
/// is set to show them. In a column the card grows taller to fit the buttons under
/// the art.
struct NowPlayingWidget: View {
    let tile: WidgetTile

    @Environment(\.self) private var environment
    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @State private var hovering = false

    private var track: NowPlayingTrack? { monitor.track }
    private var layout: NowPlayingLayout { tile.nowPlayingLayout }
    private var tall: Bool { vertical && tile.showsControls }
    /// The art alone on a tile the size of an app icon: always in a column, and in
    /// a row when the layout is the art and there are no buttons to sit beside it.
    private var square: Bool { vertical || (layout == .artwork && !tile.showsControls) }

    var body: some View {
        Group {
            if tall {
                // Larger art with play/pause badged on it; previous and next underneath.
                VStack(spacing: environment.scaled(3)) {
                    Button(action: playPause) {
                        artwork(side: environment.scaled(38))
                            .overlay(playBadge)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: environment.scaled(6)) {
                        controlButton("backward.fill", help: "Previous track") { monitor.send(.previous) }
                        controlButton("forward.fill", help: "Next track") { monitor.send(.next) }
                    }
                    .disabled(track == nil)
                    .opacity(track == nil ? 0.4 : 1)
                }
            } else if vertical {
                Button(action: playPause) {
                    trackView.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: environment.scaled(6)) {
                    Button(action: playPause) {
                        trackView.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if tile.showsControls {
                        controls
                    }
                }
            }
        }
        .widgetCard(square: square, height: tall ? size * 1.36 : nil)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                .fill(DockPalette.onSlab.opacity(hovering ? 0.08 : 0))
                .allowsHitTesting(false)
        )
        .onHover { hovering = $0 }
        .dockTooltip(
            track.map { "\($0.title)\($0.artist.isEmpty ? "" : " — \($0.artist)")" } ?? "Not playing",
            track.map { "\($0.player.title) · click to \($0.isPlaying ? "pause" : "play")" } ?? "Open Music or Spotify and start something"
        )
        .dockContextMenu { menu }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    // MARK: Pieces

    /// Play or pause, sitting on the art: a dark disc that reads on any cover.
    private var playBadge: some View {
        let disc = environment.scaled(18)
        return Circle()
            .fill(.black.opacity(track == nil ? 0.25 : 0.5))
            .frame(width: disc, height: disc)
            .overlay(
                Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: disc * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    /// The art with what the layout puts beside it: the title and the artist, the
    /// title alone, or nothing — and in a column, a play glyph under the art, since
    /// there is no room for words. Each line stops at the layout's width, so a long
    /// title crops rather than pushing the dock wider; the whole of it is in the
    /// tooltip.
    private var trackView: some View {
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: environment.scaled(8)))
        return stack {
            if layout == .artwork {
                // Play and pause sit on the art, unless the buttons beside it already carry them.
                let art = artwork(side: environment.scaled(vertical ? 34 : 38))
                if square { art.overlay(playBadge) } else { art }
            } else {
                artwork(side: environment.scaled(vertical ? 24 : 30))
                if vertical {
                    Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: environment.scaled(9), weight: .bold))
                        .foregroundStyle(DockPalette.onSlab.opacity(track == nil ? 0.4 : 0.8))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track?.title ?? "Not playing")
                            .font(.system(size: environment.scaled(13), weight: .semibold))
                            .lineLimit(1)
                        if layout == .full {
                            Text(track.map { $0.artist.isEmpty ? $0.player.title : $0.artist } ?? "Music or Spotify")
                                .font(.system(size: environment.scaled(10), weight: .medium))
                                .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: environment.scaled(layout.textWidth), alignment: .leading)
                }
            }
        }
        .fixedSize(horizontal: !vertical, vertical: false)
        .opacity(track == nil ? 0.7 : 1)
    }

    /// The album art when it has arrived, the player's icon until then, a note with nothing on.
    @ViewBuilder
    private func artwork(side: CGFloat) -> some View {
        if let art = monitor.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
                .saturation(track?.isPlaying == true ? 1 : 0.4)
        } else if let icon = track?.player.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: side, height: side)
                .saturation(track?.isPlaying == true ? 1 : 0.4)
        } else {
            RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
                .fill(DockPalette.onSlab.opacity(0.12))
                .frame(width: side, height: side)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.5, weight: .medium))
                        .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                )
        }
    }

    /// Previous, play/pause and next, in a row beside the track.
    private var controls: some View {
        HStack(spacing: environment.scaled(2)) {
            controlButton("backward.fill", help: "Previous track") { monitor.send(.previous) }
            controlButton(track?.isPlaying == true ? "pause.fill" : "play.fill", help: "Play or pause", action: playPause)
            controlButton("forward.fill", help: "Next track") { monitor.send(.next) }
        }
        .disabled(track == nil)
        .opacity(track == nil ? 0.4 : 1)
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            DockTooltipController.shared.cancel()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: environment.scaled(11), weight: .semibold))
                .frame(width: environment.scaled(vertical ? 20 : 24), height: environment.scaled(vertical ? 18 : 24))
                .contentShape(Rectangle())
        }
        .buttonStyle(ControlButtonStyle(cornerRadius: environment.scaled(5)))
    }

    @ViewBuilder
    private var menu: some View {
        Button(track?.isPlaying == true ? "Pause" : "Play") { monitor.send(.playPause) }
        Button("Next Track") { monitor.send(.next) }
        Button("Previous Track") { monitor.send(.previous) }
        Divider()
        if let player = track?.player ?? MediaPlayer.allCases.first(where: { $0.runningApplication != nil }) {
            Button("Open \(player.title)") { monitor.revealPlayer() }
        }
        Button("Refresh") { monitor.refresh() }
    }

    private func playPause() {
        DockTooltipController.shared.cancel()
        monitor.send(.playPause)
    }
}

/// A small transport button that lights up under the pointer and dims while pressed.
private struct ControlButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DockPalette.onSlab.opacity(configuration.isPressed ? 0.2 : (hovering ? 0.12 : 0)))
            )
            .onHover { hovering = $0 }
    }
}

// MARK: - AI usage

/// What is left of the Claude and Copilot allowances: a card per service, each
/// showing the tightest of its main windows as a number, a ring or a bar, opening
/// into every window with its reset time. The monitor reads each service's own
/// sign-in, so there is nothing to set up beyond ticking the services on the card.
struct AIUsageWidget: View {
    let tile: WidgetTile

    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = AIUsageMonitor.shared

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if tile.usageServices.isEmpty {
                VStack(spacing: 2) {
                    Image(systemName: WidgetKind.aiUsage.symbolName)
                        .font(.system(size: environment.scaled(18)))
                    Text("Usage")
                        .font(.system(size: environment.scaled(9), weight: .semibold))
                }
                .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                .widgetCard(square: vertical)
                .dockTooltip("AI Usage", "Choose Claude or Copilot on the widget's card in the editor")
            } else {
                ForEach(tile.usageServices) { service in
                    UsageServiceCard(tile: tile, service: service)
                }
            }
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }
}

/// A ring filled clockwise from the top to the fraction, the way an Activity ring
/// is: on a track of its own colour, brightening along the arc, with a soft glow
/// of the colour behind it so it reads as lit rather than painted.
/// A ring filled to a fraction, the way macOS draws its batteries: a flat arc
/// with round ends on a faint track, starting at the top. For allowances and
/// batteries alike, so the two read as one.
struct LevelRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat

    /// The stroke for a ring of the diameter, the same on every ring.
    static func lineWidth(for diameter: CGFloat) -> CGFloat { max(2.5, diameter * 0.11) }

    private var clamped: Double { max(0, min(1, fraction)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DockPalette.onSlab.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.5), value: clamped)
    }
}

/// One service on a card. Orange, red under a tenth; a dash while there is
/// nothing to show.
private struct UsageServiceCard: View {
    let tile: WidgetTile
    let service: UsageService

    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @Environment(\.dockEdge) private var edge
    @ObservedObject private var monitor = AIUsageMonitor.shared
    /// The stack is keyed by widget; each card is a widget of its own to it.
    @State private var stackID = UUID()

    private var report: UsageReport? { monitor.reports[service] }
    private var problem: UsageProblem? { monitor.problems[service] }
    private var remaining: Double? { report?.lowestRemaining }

    private var tint: Color {
        guard let remaining else { return DockPalette.onSlab.opacity(0.35) }
        return Self.tint(for: remaining)
    }

    private var percentText: String {
        remaining.map { "\(Int($0.rounded()))" } ?? "–"
    }

    var body: some View {
        CardButton(action: open) {
            Group {
                switch tile.usageLayout {
                case .numbers: numbers
                case .rings: rings
                case .bars: bars
                }
            }
            // Stale numbers fade a little while a refresh that failed is the latest word.
            .opacity(problem != nil && report != nil ? 0.7 : 1)
        }
        .dockTooltip(tooltipTitle, tooltipDetail)
        .dockContextMenu {
            Button("Refresh") { monitor.refresh(service, interactive: true) }
                .disabled(monitor.refreshing.contains(service))
            Button("Open \(service.title) Usage Page") { NSWorkspace.shared.open(service.usagePage) }
        }
    }

    // MARK: Layouts

    /// The percentage large, the service under it.
    private var numbers: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(percentText)
                    .font(.system(size: environment.scaled(vertical ? 15 : 19), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if remaining != nil {
                    Text("%")
                        .font(.system(size: environment.scaled(vertical ? 8 : 10), weight: .semibold, design: .rounded))
                        .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                }
            }
            .foregroundStyle(remaining == nil ? DockPalette.onSlab.opacity(0.5) : DockPalette.onSlab)
            label(size: vertical ? 8 : 10)
        }
    }

    /// A ring with the percentage inside, the service under it: the same ring as a
    /// battery's, with its level. The "%" only comes in once the ring is big
    /// enough to hold it under the number without crowding.
    private var rings: some View {
        let side = environment.scaled(28)
        let lineWidth = LevelRing.lineWidth(for: side)
        // The number stays clear of the ring: "100" shrinks to fit the inside.
        let inside = side - lineWidth * 2 - side * 0.12
        let showsSign = side >= 40 && remaining != nil
        return VStack(spacing: environment.scaled(2)) {
            LevelRing(fraction: (remaining ?? 0) / 100, color: tint, lineWidth: lineWidth)
                .frame(width: side, height: side)
                .overlay(
                    VStack(spacing: -2) {
                        Text(percentText)
                            .font(.system(size: side * 0.4, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(remaining == nil ? DockPalette.onSlab.opacity(0.5) : DockPalette.onSlab)
                        if showsSign {
                            Text("%")
                                .font(.system(size: side * 0.2, weight: .semibold, design: .rounded))
                                .foregroundStyle(DockPalette.onSlab.opacity(0.55))
                        }
                    }
                    .frame(width: inside)
                )
            label(size: vertical ? 8 : 9)
        }
    }

    /// The service and percentage on one line, a bar under them.
    private var bars: some View {
        let width = environment.scaled(vertical ? 36 : 92)
        let bar = Capsule()
            .fill(DockPalette.onSlab.opacity(0.14))
            .frame(width: width, height: environment.scaled(vertical ? 4 : 5))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .frame(width: width * (remaining ?? 0) / 100)
                    .animation(.easeOut(duration: 0.4), value: remaining)
            }
        return Group {
            if vertical {
                VStack(spacing: environment.scaled(3)) {
                    Text(remaining.map { "\(Int($0.rounded()))%" } ?? "–")
                        .font(.system(size: environment.scaled(11), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    bar
                    label(size: 8)
                }
            } else {
                VStack(alignment: .leading, spacing: environment.scaled(4)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(service.title)
                            .font(.system(size: environment.scaled(12), weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(remaining.map { "\(Int($0.rounded()))%" } ?? "–")
                            .font(.system(size: environment.scaled(11), weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                    }
                    .frame(width: width)
                    bar
                }
            }
        }
    }

    private func label(size: CGFloat) -> some View {
        Text(service.title)
            .font(.system(size: environment.scaled(size), weight: .semibold))
            .foregroundStyle(DockPalette.onSlab.opacity(0.6))
            .lineLimit(1)
    }

    // MARK: Tooltip

    private var tooltipTitle: String {
        if let remaining { return "\(service.title) — \(Int(remaining.rounded()))% left" }
        return "\(service.title) — \(problem?.title ?? "Loading…")"
    }

    private var tooltipDetail: String {
        if let report {
            let windows = report.windows.filter(\.isPrimary)
                .map { "\($0.title) \(Int($0.remaining.rounded()))%" }
                .joined(separator: " · ")
            if let problem { return "\(windows) · \(problem.hint(for: service))" }
            return "\(windows) · click for details"
        }
        return problem?.hint(for: service) ?? "Reading \(service.title)'s usage"
    }

    // MARK: Stack

    /// Every window with its reset, or what went wrong.
    private func open() {
        DockTooltipController.shared.cancel()
        let now = Date()
        var items: [DockStackItem] = []
        if let report {
            for window in report.windows {
                var parts = ["\(Int(window.remaining.rounded()))% left"]
                if let detail = window.detail { parts.append(detail) }
                if let reset = Self.resetText(window, now: now) { parts.append(reset) }
                items.append(DockStackItem(
                    id: window.id,
                    title: window.title,
                    subtitle: parts.joined(separator: " · "),
                    icon: .ring(window.remaining / 100, Self.tint(for: window.remaining)),
                    action: { NSWorkspace.shared.open(service.usagePage) }
                ))
            }
        }
        if let problem {
            items.append(DockStackItem(
                id: "problem",
                title: problem.title,
                subtitle: problem.hint(for: service),
                icon: .symbol("exclamationmark.triangle", .orange),
                action: { AIUsageMonitor.shared.refresh(service, interactive: true) }
            ))
        }
        var title = service.title
        if let plan = report?.plan { title += " · \(Self.planTitle(plan))" }
        if let fetched = report?.fetchedAt { title += " · updated \(Self.ago(fetched, now: now))" }
        DockStackController.shared.toggle(
            for: stackID,
            content: DockStackContent(
                title: title,
                items: items,
                style: .list,
                emptyText: "Reading \(service.title)'s usage…",
                footer: DockStackItem(
                    id: "refresh",
                    title: "Refresh",
                    icon: .symbol("arrow.clockwise", DockPalette.onSlab),
                    action: { AIUsageMonitor.shared.refresh(service, interactive: true) }
                )
            ),
            edge: edge
        )
    }

    private static func tint(for remaining: Double) -> Color {
        remaining <= 10 ? .red : .orange
    }

    /// "Resets Thu 12:10 PM · 2h 20m", or "Resets Oct 1 · 14d" for a day.
    private static func resetText(_ window: UsageWindow, now: Date) -> String? {
        guard let reset = window.resetsAt else { return nil }
        let calendar = Calendar.current
        let when: String
        if window.resetsOnDay {
            when = reset.formatted(.dateTime.month(.abbreviated).day())
        } else if calendar.isDate(reset, inSameDayAs: now) {
            when = reset.formatted(date: .omitted, time: .shortened)
        } else {
            when = reset.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        let seconds = max(0, reset.timeIntervalSince(now))
        let countdown: String
        if window.resetsOnDay {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: reset)).day ?? 0
            countdown = days <= 0 ? "today" : "\(days)d"
        } else if seconds >= 86_400 {
            countdown = "\(Int(seconds / 86_400))d \(Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600))h"
        } else if seconds >= 3600 {
            countdown = "\(Int(seconds / 3600))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))m"
        } else {
            countdown = "\(Int(seconds / 60))m"
        }
        return "resets \(when) · \(countdown)"
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }

    /// "individual_pro" as GitHub sends it → "Pro".
    private static func planTitle(_ plan: String) -> String {
        plan.replacingOccurrences(of: "individual_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
