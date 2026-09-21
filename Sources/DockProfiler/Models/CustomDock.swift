import AppKit
import SwiftUI

/// A widget in Dock Profiler's own dock. The macOS Dock has no extension point —
/// `persistent-apps` only takes files, folders, links and spacers — so widgets are
/// drawn in a floating panel of our own (see `CustomDockWindowController`).
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock
    case date
    case battery
    case accessories
    case agents
    case nowPlaying
    case profiles
    case trash
    case airDrop
    case folderStack
    case appStack
    case aiUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .date: return "Date"
        case .battery: return "Battery"
        case .accessories: return "Accessories"
        case .agents: return "Agents"
        case .nowPlaying: return "Now Playing"
        case .profiles: return "Profiles"
        case .trash: return "Trash"
        case .airDrop: return "AirDrop"
        case .folderStack: return "Folder"
        case .appStack: return "App Stack"
        case .aiUsage: return "AI Usage"
        }
    }

    var symbolName: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .battery: return "battery.75percent"
        case .accessories: return "airpodspro"
        case .agents: return "sparkles.rectangle.stack"  // drawn as Lucide's bot in the UI; see BotGlyph
        case .nowPlaying: return "music.note"
        case .profiles: return "square.grid.2x2"
        case .trash: return "trash"
        case .airDrop: return "dot.radiowaves.up.forward"
        case .folderStack: return "folder"
        case .appStack: return "square.stack.3d.up"
        case .aiUsage: return "gauge.with.dots.needle.33percent"
        }
    }

    var summary: String {
        switch self {
        case .clock: return "Hours and minutes"
        case .date: return "Weekday and day"
        case .battery: return "Charge and charging"
        case .accessories: return "AirPods, keyboard, mouse and trackpad batteries"
        case .agents: return "Agent Frame sessions"
        case .nowPlaying: return "Music or Spotify"
        case .profiles: return "Switch Dock Profiler profiles"
        case .trash: return "The Trash, with files dropped on it"
        case .airDrop: return "Send files dropped on it to a nearby device"
        case .folderStack: return "A folder that opens into its files"
        case .appStack: return "Apps folded into one tile"
        case .aiUsage: return "What is left of your Claude and Copilot allowances"
        }
    }

    /// Widgets that carry settings of their own, shown on their card in the editor.
    var isConfigurable: Bool {
        switch self {
        case .folderStack, .appStack, .accessories, .agents, .nowPlaying, .aiUsage: return true
        default: return false
        }
    }
}

/// The services the AI Usage widget can track. Each is read the way its own tools
/// leave it on this Mac — no signing in to Dock Profiler itself.
enum UsageService: String, Codable, CaseIterable, Identifiable {
    case claude
    case copilot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .copilot: return "Copilot"
        }
    }

    /// Where the full picture lives on the web.
    var usagePage: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        case .copilot: return URL(string: "https://github.com/settings/copilot/features")!
        }
    }

    /// What signing in means for this service, for the empty state.
    var signInHint: String {
        switch self {
        case .claude: return "Sign in to Claude Code in a terminal; its token is read from the Keychain"
        case .copilot: return "Sign in to GitHub Copilot in VS Code or Xcode; its token is read from ~/.config/github-copilot"
        }
    }
}

/// How the AI Usage widget draws each service's remaining allowance.
enum UsageLayout: String, Codable, CaseIterable, Identifiable {
    case numbers
    case rings
    case bars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .numbers: return "Numbers"
        case .rings: return "Rings"
        case .bars: return "Bars"
        }
    }
}

/// How the Agents widget draws the sessions Agent Frame is tracking.
enum AgentsLayout: String, Codable, CaseIterable, Identifiable {
    /// A card per session: folder and state on a chip, or a tile in a column.
    case each
    /// One tile with a count in the colour of the most urgent session, that opens into the list.
    case one
    /// The icon and the count alone, a tile the size of an app icon.
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .each: return "Each agent"
        case .one: return "One tile"
        case .minimal: return "Minimal"
        }
    }

    var summary: String {
        switch self {
        case .each: return "A card per session"
        case .one: return "One tile that opens into the sessions"
        case .minimal: return "The icon and a count"
        }
    }
}

/// How the Accessories widget draws each battery: a tile the size of an app icon
/// with the device's icon inside a ring that empties with it.
enum AccessoryLayout: String, Codable, CaseIterable, Identifiable {
    /// The ring, with the level under it.
    case ring
    /// The ring alone.
    case ringOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring: return "Ring and level"
        case .ringOnly: return "Ring"
        }
    }

    var summary: String {
        switch self {
        case .ring: return "as rings with their level"
        case .ringOnly: return "as rings"
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
    /// Agents: a card per session, one tile with a count that opens into the list, or the icon and count alone.
    var agentsLayout: AgentsLayout = .each
    /// Accessories: how each battery is drawn, which accessories are left out, and
    /// whether this Mac's own battery sits among them. Accessories are shown unless
    /// hidden, so a new one appears as soon as it connects.
    var accessoryLayout: AccessoryLayout = .ring
    var hiddenAccessoryIDs: [String] = []
    var showsMacBattery: Bool = false
    /// Now playing: previous and next buttons beside the track.
    var showsControls: Bool = false
    /// AI usage: how the allowances are drawn, and which services are tracked, in order.
    var usageLayout: UsageLayout = .rings
    var usageServices: [UsageService] = UsageService.allCases

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
            return agentsLayout == .each ? kind.summary : agentsLayout.summary
        case .accessories:
            var shown = hiddenAccessoryIDs.isEmpty ? "Every accessory" : "Every accessory but \(hiddenAccessoryIDs.count)"
            if showsMacBattery { shown += " and this Mac" }
            return "\(shown), \(accessoryLayout.summary)"
        case .nowPlaying:
            return showsControls ? "Music or Spotify, with skip buttons" : kind.summary
        case .aiUsage:
            guard !usageServices.isEmpty else { return "Nothing tracked yet" }
            let names = usageServices.map(\.title)
            let tracked = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
            return "\(tracked), as \(usageLayout.title.lowercased())"
        default:
            return kind.summary
        }
    }

    // Fields added in later versions are missing from earlier files.
    private enum CodingKeys: String, CodingKey {
        case id, kind, anchor, path, apps, agentsLayout, showsControls, usageLayout, usageServices
        case accessoryLayout, hiddenAccessoryIDs, showsMacBattery
    }

    /// Keys earlier versions wrote and this one only reads.
    private enum LegacyKeys: String, CodingKey {
        /// Agents, before there were three layouts: true for one tile, false for a card per session.
        case stacked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(WidgetKind.self, forKey: .kind)
        anchor = try container.decodeIfPresent(WidgetAnchor.self, forKey: .anchor) ?? .end
        path = try container.decodeIfPresent(String.self, forKey: .path)
        apps = try container.decodeIfPresent([DockTile].self, forKey: .apps) ?? []
        // A layout this build does not know — from a newer one — falls back to the
        // default rather than making the whole file unreadable. Before there were
        // three, `stacked` chose between the first two.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let stacked = try legacy.decodeIfPresent(Bool.self, forKey: .stacked) ?? false
        agentsLayout = (try? container.decodeIfPresent(String.self, forKey: .agentsLayout))
            .flatMap(AgentsLayout.init(rawValue:)) ?? (stacked ? .one : .each)
        showsControls = try container.decodeIfPresent(Bool.self, forKey: .showsControls) ?? false
        usageLayout = try container.decodeIfPresent(UsageLayout.self, forKey: .usageLayout) ?? .rings
        usageServices = try container.decodeIfPresent([UsageService].self, forKey: .usageServices) ?? UsageService.allCases
        // A layout this build does not know — from a newer one, or an earlier name —
        // falls back to the default rather than making the whole file unreadable.
        accessoryLayout = (try? container.decodeIfPresent(String.self, forKey: .accessoryLayout))
            .flatMap(AccessoryLayout.init(rawValue:)) ?? .ring
        hiddenAccessoryIDs = try container.decodeIfPresent([String].self, forKey: .hiddenAccessoryIDs) ?? []
        showsMacBattery = try container.decodeIfPresent(Bool.self, forKey: .showsMacBattery) ?? false
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

/// Where the dock sits on a screen: its edge and, along a top or bottom edge, the
/// end it hugs.
struct DockPlacement: Codable, Hashable {
    var edge: DockStripEdge = .bottom
    var alignment: DockStripAlignment = .trailing

    /// "Bottom, right" — or just "Left" for a side edge, which is always centred.
    var title: String {
        edge.isVertical ? edge.title : "\(edge.title), \(alignment.title.lowercased())"
    }
}

/// Which displays the dock is drawn on.
enum DockDisplays: String, Codable, CaseIterable, Identifiable {
    /// The main display — the one with the menu bar, where the macOS Dock lives.
    case main
    /// Every display, each with a dock of its own on the same edge, or one it is
    /// given in `CustomDockOptions.displayPlacements`.
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: return "Main display"
        case .all: return "All displays"
        }
    }
}

/// How the slab is drawn: the material behind the tiles, and whether the dock
/// keeps its own appearance regardless of the system's.
enum DockStyle: String, Codable, CaseIterable, Identifiable {
    /// The Dock's own look: translucent, light in Light Mode and dark in Dark Mode.
    case system
    case light
    case dark
    /// macOS Tahoe's glass, refracting what is behind it. Drawn as `system` before it.
    case liquidGlass
    /// No slab at all: the tiles sit straight on the desktop, each widget on its own card.
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Follow the system"
        case .light: return "Light glass"
        case .dark: return "Dark glass"
        case .liquidGlass: return "Liquid Glass"
        case .transparent: return "Transparent"
        }
    }

    var summary: String {
        switch self {
        case .system: return "Light or dark with the rest of the Mac, as the Dock is"
        case .light: return "Light, whatever the system appearance"
        case .dark: return "Dark, whatever the system appearance"
        case .liquidGlass: return "Refracts what is behind it, light or dark to suit the wallpaper, like the Tahoe Dock"
        case .transparent: return "No slab — the tiles sit straight on the desktop, light or dark to suit the wallpaper, each widget on its own card"
        }
    }

    /// Whether there is a slab behind the tiles at all.
    var hasPlate: Bool { self != .transparent }

    /// The appearance forced on the dock's windows — nil to follow the system.
    var forcedAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system, .liquidGlass, .transparent: return nil
        }
    }

    /// The SwiftUI side of `forcedAppearance`, for the preview in the editor.
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system, .liquidGlass, .transparent: return nil
        }
    }

    /// Whether the desktop shows through enough that the tiles read against it
    /// rather than against a slab: glass, or no slab at all. The dock then takes
    /// its appearance from the desktop picture, as the Tahoe Dock does.
    var showsDesktop: Bool {
        switch self {
        case .liquidGlass: return Self.supportsLiquidGlass
        case .transparent: return true
        case .system, .light, .dark: return false
        }
    }

    /// Whether this Mac can draw Liquid Glass.
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// The styles worth offering here: Liquid Glass only where it can be drawn.
    static var available: [DockStyle] {
        allCases.filter { $0 != .liquidGlass || supportsLiquidGlass }
    }
}

/// How much room the slab leaves around and between its tiles. The corner radius
/// follows, so a tighter dock is also a squarer one.
enum DockDensity: String, Codable, CaseIterable, Identifiable {
    case compact, regular, roomy

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// The slab's inset around the tiles, and the gap between them, in points.
    var padding: CGFloat {
        switch self {
        case .compact: return 4
        case .regular: return 8
        case .roomy: return 12
        }
    }
}

/// The slab's look: its style, whether it blurs what is behind it, whether it takes
/// the profile's colour, whether widgets get cards, and how tightly it is packed.
struct DockLook: Codable, Hashable {
    var style: DockStyle = .system
    /// Blur what is behind the slab; off draws it solid — or, for Liquid Glass,
    /// clear. Solid regardless while macOS's Reduce transparency is on.
    var translucent: Bool = true
    /// A wash of the profile's colour over the slab, so each profile's dock is its own.
    var tinted: Bool = false
    /// A card behind each widget, as the Dock's tiles have. Always on without a slab.
    var tileCards: Bool = true
    var density: DockDensity = .regular

    init() {}

    // Fields added in later versions are missing from earlier files.
    private enum CodingKeys: String, CodingKey {
        case style, translucent, tinted, tileCards, density
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DockLook()
        style = try container.decodeIfPresent(DockStyle.self, forKey: .style) ?? defaults.style
        translucent = try container.decodeIfPresent(Bool.self, forKey: .translucent) ?? defaults.translucent
        tinted = try container.decodeIfPresent(Bool.self, forKey: .tinted) ?? defaults.tinted
        tileCards = try container.decodeIfPresent(Bool.self, forKey: .tileCards) ?? defaults.tileCards
        density = try container.decodeIfPresent(DockDensity.self, forKey: .density) ?? defaults.density
    }

    /// Cards are what hold a widget together once there is no slab.
    var drawsTileCards: Bool { tileCards || !style.hasPlate }
}

/// The optional custom-dock half of a profile. When `enabled` is false — or the
/// dock would be empty — activating the profile takes the panel away.
struct CustomDockOptions: Codable, Hashable {
    var enabled: Bool = false
    var mode: CustomDockMode = .detached
    var edge: DockStripEdge = .bottom
    var alignment: DockStripAlignment = .trailing
    var displays: DockDisplays = .main
    /// Displays with a position of their own, keyed by `NSScreen.persistentID` so
    /// a display keeps its place when it is unplugged and plugged back in. Every
    /// other display takes `edge` and `alignment`. Two side-by-side displays can
    /// then keep their docks on the outer edges, leaving the shared edge clear
    /// for the pointer to cross.
    var displayPlacements: [String: DockPlacement] = [:]
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
    /// The Dock's notification badges on the app tiles. Read from the Dock through
    /// Accessibility, so it needs that permission — off until asked for.
    var showsBadges: Bool = false
    var look = DockLook()
    var widgets: [WidgetTile] = []

    var isCombined: Bool { enabled && mode == .combined }

    /// The position every display takes unless it has one of its own.
    var placement: DockPlacement {
        get { DockPlacement(edge: edge, alignment: alignment) }
        set { edge = newValue.edge; alignment = newValue.alignment }
    }

    /// Where the dock sits on `screen`: its own position when it has one and the
    /// dock is on every display, otherwise the shared one.
    func placement(for screen: NSScreen) -> DockPlacement {
        guard displays == .all, let key = screen.persistentID, let own = displayPlacements[key] else {
            return placement
        }
        return own
    }

    /// The screens the dock is drawn on right now. The main display is always
    /// first in the list.
    var screens: [NSScreen] {
        displays == .all ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
    }

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
        case enabled, mode, edge, alignment, displays, displayPlacements, autohide, edgeHint, tileSize, magnification, magnifiedSize, showsRunningApps, showsBadges, look, widgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CustomDockOptions()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        mode = try container.decodeIfPresent(CustomDockMode.self, forKey: .mode) ?? defaults.mode
        edge = try container.decodeIfPresent(DockStripEdge.self, forKey: .edge) ?? defaults.edge
        alignment = try container.decodeIfPresent(DockStripAlignment.self, forKey: .alignment) ?? defaults.alignment
        displays = try container.decodeIfPresent(DockDisplays.self, forKey: .displays) ?? defaults.displays
        displayPlacements = try container.decodeIfPresent([String: DockPlacement].self, forKey: .displayPlacements) ?? defaults.displayPlacements
        autohide = try container.decodeIfPresent(Bool.self, forKey: .autohide) ?? defaults.autohide
        edgeHint = try container.decodeIfPresent(Bool.self, forKey: .edgeHint) ?? defaults.edgeHint
        tileSize = try container.decodeIfPresent(Double.self, forKey: .tileSize) ?? defaults.tileSize
        magnification = try container.decodeIfPresent(Bool.self, forKey: .magnification) ?? defaults.magnification
        magnifiedSize = try container.decodeIfPresent(Double.self, forKey: .magnifiedSize) ?? defaults.magnifiedSize
        showsRunningApps = try container.decodeIfPresent(Bool.self, forKey: .showsRunningApps) ?? defaults.showsRunningApps
        showsBadges = try container.decodeIfPresent(Bool.self, forKey: .showsBadges) ?? defaults.showsBadges
        look = try container.decodeIfPresent(DockLook.self, forKey: .look) ?? defaults.look
        widgets = try container.decodeIfPresent([WidgetTile].self, forKey: .widgets) ?? defaults.widgets
    }
}
