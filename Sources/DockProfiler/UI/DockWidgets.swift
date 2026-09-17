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
    @ViewBuilder let content: () -> Content

    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .widgetCard(square: vertical)
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
        .contextMenu {
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
    @ObservedObject private var running = RunningAppsMonitor.shared

    var body: some View {
        IconTile(action: open) {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(DockPalette.onSlab.opacity(0.12))
                .overlay(preview.padding(size * 0.1))
        }
        .dockTooltip(
            tile.apps.isEmpty ? "App Stack" : "\(tile.apps.count) app\(tile.apps.count == 1 ? "" : "s")",
            tile.apps.isEmpty ? "Add apps in the profile editor" : tile.apps.prefix(4).map(\.label).joined(separator: ", ")
        )
    }

    /// Up to four icons in a two-by-two grid; fewer sit centred.
    @ViewBuilder
    private var preview: some View {
        let shown = Array(tile.apps.prefix(4))
        if shown.isEmpty {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: size * 0.36))
                .foregroundStyle(DockPalette.onSlab.opacity(0.7))
        } else {
            let columns = shown.count == 1 ? 1 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
                ForEach(shown) { app in
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable()
                        } else {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func open() {
        DockTooltipController.shared.cancel()
        let items = tile.apps.map { app in
            DockStackItem(
                id: app.id.uuidString,
                title: app.label,
                subtitle: app.subtitle,
                icon: app.icon.map { .image($0) } ?? .symbol("app.dashed", DockPalette.onSlab),
                isCurrent: running.isRunning(app),
                action: { app.open() }
            )
        }
        DockStackController.shared.toggle(
            for: tile.id,
            content: DockStackContent(
                title: tile.apps.isEmpty ? "App Stack" : "\(tile.apps.count) apps",
                items: items,
                style: .grid,
                emptyText: "Add apps to this stack in the profile editor"
            ),
            edge: edge
        )
    }
}

// MARK: - Agents, stacked

/// The agents widget folded into one tile: a count in the colour of the most urgent
/// session, opening into the list. `AgentsWidget` keeps the monitor running.
struct AgentsStackTile: View {
    let tile: WidgetTile

    @Environment(\.self) private var environment
    @Environment(\.dockVertical) private var vertical
    @Environment(\.dockEdge) private var edge
    @ObservedObject private var monitor = AgentSessionMonitor.shared

    /// Sessions come most urgent first.
    private var urgent: AgentState? { monitor.sessions.first?.state }

    var body: some View {
        CardButton(action: open) {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: environment.scaled(8)))
            layout {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: environment.scaled(vertical ? 16 : 20)))
                    .foregroundStyle(monitor.sessions.isEmpty ? DockPalette.onSlab.opacity(0.5) : DockPalette.onSlab)
                    .overlay(alignment: .topTrailing) {
                        if !monitor.sessions.isEmpty {
                            CountBadge(count: monitor.sessions.count, color: Color(nsColor: (urgent ?? .idle).color))
                                .offset(x: environment.scaled(8), y: -environment.scaled(6))
                        }
                    }
                if !vertical {
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
        .contextMenu {
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
        .contextMenu {
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
/// arrives — with the track beside it. Click to play or pause; skip from the context
/// menu, or from the buttons when the widget is set to show them. In a column the
/// card grows taller to fit the buttons under the art.
struct NowPlayingWidget: View {
    let tile: WidgetTile

    @Environment(\.self) private var environment
    @Environment(\.dockTileSize) private var size
    @Environment(\.dockVertical) private var vertical
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @State private var hovering = false

    private var track: NowPlayingTrack? { monitor.track }
    private var tall: Bool { vertical && tile.showsControls }

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
        .widgetCard(square: vertical, height: tall ? size * 1.36 : nil)
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
        .contextMenu { menu }
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

    private var trackView: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: environment.scaled(8)))
        return layout {
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
                    Text(track.map { $0.artist.isEmpty ? $0.player.title : $0.artist } ?? "Music or Spotify")
                        .font(.system(size: environment.scaled(10), weight: .medium))
                        .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: environment.scaled(180), alignment: .leading)
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
