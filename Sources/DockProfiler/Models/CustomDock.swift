import Foundation

/// A widget in Dock Profiler's own dock. The macOS Dock has no extension point —
/// `persistent-apps` only takes files, folders, links and spacers — so widgets are
/// drawn in a floating panel of our own (see `CustomDockWindowController`).
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock
    case date
    case battery
    case agents
    case nowPlaying
    case profiles
    case trash
    case folderStack
    case appStack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .date: return "Date"
        case .battery: return "Battery"
        case .agents: return "Agents"
        case .nowPlaying: return "Now Playing"
        case .profiles: return "Profiles"
        case .trash: return "Trash"
        case .folderStack: return "Folder"
        case .appStack: return "App Stack"
        }
    }

    var symbolName: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .battery: return "battery.75percent"
        case .agents: return "sparkles.rectangle.stack"
        case .nowPlaying: return "music.note"
        case .profiles: return "square.grid.2x2"
        case .trash: return "trash"
        case .folderStack: return "folder"
        case .appStack: return "square.stack.3d.up"
        }
    }

    var summary: String {
        switch self {
        case .clock: return "Hours and minutes"
        case .date: return "Weekday and day"
        case .battery: return "Charge and charging"
        case .agents: return "Agent Frame sessions"
        case .nowPlaying: return "Music or Spotify"
        case .profiles: return "Switch Dock Profiler profiles"
        case .trash: return "The Trash, with files dropped on it"
        case .folderStack: return "A folder that opens into its files"
        case .appStack: return "Apps folded into one tile"
        }
    }

    /// Widgets that carry settings of their own, shown on their card in the editor.
    var isConfigurable: Bool {
        switch self {
        case .folderStack, .appStack, .agents, .nowPlaying: return true
        default: return false
        }
    }
}

/// Where a widget sits among the apps when the dock is combined. Anchoring to an
/// app's path rather than its position means the widget stays next to that app
/// when the Dock is rearranged underneath the profile (auto-save replaces the app
/// list wholesale, so positions and tile ids would not survive).
enum WidgetAnchor: Codable, Hashable {
    case start
    case end
    case after(String)
    /// After the app at the path — or the start of the row, with nil — and then that
    /// many spacers. Spacers have no path of their own, so a widget between an app
    /// and its spacer, or between two spacers, counts them from the last app.
    case afterSpacers(String?, Int)
}

struct WidgetTile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: WidgetKind
    var anchor: WidgetAnchor = .end
    /// Folder stack: the folder it opens into.
    var path: String?
    /// App stack: the apps folded into it.
    var apps: [DockTile] = []
    /// Agents: one tile with a count that opens into the list, rather than a chip per session.
    var stacked: Bool = false
    /// Now playing: previous and next buttons beside the track.
    var showsControls: Bool = false

    init(kind: WidgetKind, anchor: WidgetAnchor = .end) {
        self.kind = kind
        self.anchor = anchor
        if kind == .folderStack {
            path = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        }
    }

    /// What the tile is called in the dock and the editor: the folder's name, or the kind's.
    var title: String {
        switch kind {
        case .folderStack: return path.map { ($0 as NSString).lastPathComponent } ?? kind.title
        default: return kind.title
        }
    }

    /// The card's second line in the editor: the folder, the apps, or the kind's summary.
    var summary: String {
        switch kind {
        case .folderStack:
            return path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "No folder chosen"
        case .appStack:
            return apps.isEmpty ? "No apps yet" : apps.map(\.label).joined(separator: ", ")
        case .agents:
            return stacked ? "One tile that opens into the sessions" : kind.summary
        case .nowPlaying:
            return showsControls ? "Music or Spotify, with skip buttons" : kind.summary
        default:
            return kind.summary
        }
    }

    // Fields added in later versions are missing from earlier files.
    private enum CodingKeys: String, CodingKey {
        case id, kind, anchor, path, apps, stacked, showsControls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(WidgetKind.self, forKey: .kind)
        anchor = try container.decodeIfPresent(WidgetAnchor.self, forKey: .anchor) ?? .end
        path = try container.decodeIfPresent(String.self, forKey: .path)
        apps = try container.decodeIfPresent([DockTile].self, forKey: .apps) ?? []
        stacked = try container.decodeIfPresent(Bool.self, forKey: .stacked) ?? false
        showsControls = try container.decodeIfPresent(Bool.self, forKey: .showsControls) ?? false
    }
}

enum CustomDockMode: String, Codable, CaseIterable, Identifiable {
    /// Apps and widgets in one dock, standing in for the macOS Dock.
    case combined
    /// Widgets on their own, in a strip that sits beside the macOS Dock.
    case detached

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: return "Apps and widgets"
        case .detached: return "Widgets only"
        }
    }
}

enum DockStripEdge: String, Codable, CaseIterable, Identifiable {
    case bottom, top, leading, trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .leading: return "Left"
        case .trailing: return "Right"
        }
    }

    /// Left and right edges stack the items vertically, centred on the edge.
    var isVertical: Bool { self == .leading || self == .trailing }
}

/// Along a top or bottom edge, which end the strip hugs.
enum DockStripAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }
}

/// The optional custom-dock half of a profile. When `enabled` is false — or the
/// dock would be empty — activating the profile takes the panel away.
struct CustomDockOptions: Codable, Hashable {
    var enabled: Bool = false
    var mode: CustomDockMode = .detached
    var edge: DockStripEdge = .bottom
    var alignment: DockStripAlignment = .trailing
    /// Slides off screen until the pointer reaches its edge.
    var autohide: Bool = false
    /// While hidden, a slim mark stays on the edge so you know the dock is there.
    var edgeHint: Bool = true
    /// Height of an app icon or widget card, in points.
    var tileSize: Double = 56
    /// Tiles grow under the pointer, as the Dock's do.
    var magnification: Bool = false
    var magnifiedSize: Double = 84
    /// Apps that are running but not pinned, after the pinned ones — as the Dock does.
    var showsRunningApps: Bool = false
    var widgets: [WidgetTile] = []

    var isCombined: Bool { enabled && mode == .combined }

    /// How much a tile under the pointer grows, in points; zero when magnification is off.
    var magnificationExtra: Double { magnification ? max(0, magnifiedSize - tileSize) : 0 }

    var isActive: Bool {
        guard enabled else { return false }
        return mode == .combined || !widgets.isEmpty
    }

    var summary: String? {
        guard isActive else { return nil }
        if mode == .combined { return "Custom dock" }
        return "\(widgets.count) widget\(widgets.count == 1 ? "" : "s")"
    }
}

// MARK: - One row of apps and widgets

/// An item in a dock row: a Dock tile or one of our widgets. Both editor and the
/// live dock draw the same rows.
enum DockStripItem: Identifiable, Hashable {
    case tile(DockTile)
    case widget(WidgetTile)

    var id: UUID {
        switch self {
        case .tile(let tile): return tile.id
        case .widget(let widget): return widget.id
        }
    }

    var tile: DockTile? {
        if case .tile(let tile) = self { return tile }
        return nil
    }

    var widget: WidgetTile? {
        if case .widget(let widget) = self { return widget }
        return nil
    }
}

extension CustomDockOptions {
    /// Apps and widgets in one row, each widget at its anchor. Widgets whose app
    /// has gone, and those anchored to the end, come last.
    func merged(with apps: [DockTile]) -> [DockStripItem] {
        var row: [DockStripItem] = []
        var placed = Set<UUID>()

        func place(_ anchor: WidgetAnchor) {
            for widget in widgets where widget.anchor == anchor && !placed.contains(widget.id) {
                row.append(.widget(widget))
                placed.insert(widget.id)
            }
        }

        place(.start)
        var lastPath: String?
        var spacers = 0
        for app in apps {
            row.append(.tile(app))
            if let path = app.path {
                lastPath = path
                spacers = 0
                place(.after(path))
            } else if app.kind.isSpacer {
                spacers += 1
                place(.afterSpacers(lastPath, spacers))
            }
        }
        for widget in widgets where !placed.contains(widget.id) {
            row.append(.widget(widget))
        }
        return row
    }

    /// Reads the widgets back from a row the user rearranged, anchoring each to
    /// the app before it — counting any spacers in between, so a widget can sit on
    /// either side of one. Their order in the row is their order among themselves.
    static func widgets(from row: [DockStripItem]) -> [WidgetTile] {
        let lastTileIndex = row.lastIndex { $0.tile != nil }
        var result: [WidgetTile] = []
        var lastPath: String?
        var spacers = 0
        for (index, item) in row.enumerated() {
            switch item {
            case .tile(let tile):
                if let path = tile.path {
                    lastPath = path
                    spacers = 0
                } else if tile.kind.isSpacer {
                    spacers += 1
                }
            case .widget(var widget):
                if let lastTileIndex, index > lastTileIndex {
                    widget.anchor = .end
                } else if spacers > 0 {
                    widget.anchor = .afterSpacers(lastPath, spacers)
                } else if let lastPath {
                    widget.anchor = .after(lastPath)
                } else {
                    widget.anchor = .start
                }
                result.append(widget)
            }
        }
        return result
    }
}

// MARK: - Tolerant decoding

/// Fields added in later versions are missing from earlier files. Every option
/// falls back to its default instead of failing the whole store.
extension CustomDockOptions {
    private enum CodingKeys: String, CodingKey {
        case enabled, mode, edge, alignment, autohide, edgeHint, tileSize, magnification, magnifiedSize, showsRunningApps, widgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CustomDockOptions()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        mode = try container.decodeIfPresent(CustomDockMode.self, forKey: .mode) ?? defaults.mode
        edge = try container.decodeIfPresent(DockStripEdge.self, forKey: .edge) ?? defaults.edge
        alignment = try container.decodeIfPresent(DockStripAlignment.self, forKey: .alignment) ?? defaults.alignment
        autohide = try container.decodeIfPresent(Bool.self, forKey: .autohide) ?? defaults.autohide
        edgeHint = try container.decodeIfPresent(Bool.self, forKey: .edgeHint) ?? defaults.edgeHint
        tileSize = try container.decodeIfPresent(Double.self, forKey: .tileSize) ?? defaults.tileSize
        magnification = try container.decodeIfPresent(Bool.self, forKey: .magnification) ?? defaults.magnification
        magnifiedSize = try container.decodeIfPresent(Double.self, forKey: .magnifiedSize) ?? defaults.magnifiedSize
        showsRunningApps = try container.decodeIfPresent(Bool.self, forKey: .showsRunningApps) ?? defaults.showsRunningApps
        widgets = try container.decodeIfPresent([WidgetTile].self, forKey: .widgets) ?? defaults.widgets
    }
}
