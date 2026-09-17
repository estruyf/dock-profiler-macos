import Foundation
import SwiftUI

enum ProfileColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .graphite: return Color(nsColor: .systemGray)
        }
    }

    var title: String { rawValue.capitalized }
}

enum DockOrientation: String, Codable, CaseIterable, Identifiable {
    case left, bottom, right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Optional Dock look-and-feel carried by a profile. When `enabled` is false the
/// profile leaves the user's Dock settings exactly as they are.
struct DockAppearance: Codable, Hashable {
    var enabled: Bool = false
    var orientation: DockOrientation = .bottom
    var tileSize: Double = 48
    var magnification: Bool = false
    var largeSize: Double = 80
    var autohide: Bool = false
    var showRecents: Bool = true
    var minimizeIntoIcon: Bool = false
}

/// The optional desktop half of a profile: set a wallpaper when it is activated.
struct DesktopOptions: Codable, Hashable {
    var setsWallpaper: Bool = false
    var wallpaperPath: String?
    var wallpaperAllScreens: Bool = true

    var isActive: Bool { setsWallpaper && wallpaperPath != nil }

    var summary: String? { isActive ? "Wallpaper" : nil }
}

struct DockProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var color: ProfileColor = .blue
    var symbol: String = "square.grid.2x2"
    var apps: [DockTile] = []
    var others: [DockTile] = []
    /// When false the profile only swaps the app side and leaves folders/stacks alone.
    var managesOthers: Bool = false
    var appearance: DockAppearance = DockAppearance()
    var desktop: DesktopOptions = DesktopOptions()
    var customDock: CustomDockOptions = CustomDockOptions()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    func tiles(in section: DockSection) -> [DockTile] {
        section == .apps ? apps : others
    }

    /// The app row as the editor and the custom dock show it: with the widgets
    /// in among the apps when the dock is combined, apps alone otherwise.
    var appRow: [DockStripItem] {
        customDock.isCombined ? customDock.merged(with: apps) : apps.map { .tile($0) }
    }

    /// Takes a rearranged app row back: apps in their new order, widgets re-anchored.
    mutating func setAppRow(_ row: [DockStripItem]) {
        apps = row.compactMap(\.tile)
        if customDock.isCombined {
            customDock.widgets = CustomDockOptions.widgets(from: row)
        }
    }

    var itemSummary: String {
        let appCount = apps.filter { !$0.kind.isSpacer }.count
        var summary = "\(appCount) app\(appCount == 1 ? "" : "s")"
        if managesOthers, !others.isEmpty {
            summary += " · \(others.count) item\(others.count == 1 ? "" : "s")"
        }
        if let desktop = desktop.summary { summary += " · \(desktop)" }
        if let dock = customDock.summary { summary += " · \(dock)" }
        return summary
    }

    static func empty(named name: String = "New Profile") -> DockProfile {
        DockProfile(name: name)
    }
}

extension DockProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, color, symbol, apps, others, managesOthers, appearance, desktop, customDock
        case createdAt, updatedAt
    }

    /// Profiles saved by an older version lack the keys added since, so anything
    /// optional falls back to its default instead of failing the whole store.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(ProfileColor.self, forKey: .color) ?? .blue
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        apps = try container.decodeIfPresent([DockTile].self, forKey: .apps) ?? []
        others = try container.decodeIfPresent([DockTile].self, forKey: .others) ?? []
        managesOthers = try container.decodeIfPresent(Bool.self, forKey: .managesOthers) ?? false
        appearance = try container.decodeIfPresent(DockAppearance.self, forKey: .appearance) ?? DockAppearance()
        desktop = try container.decodeIfPresent(DesktopOptions.self, forKey: .desktop) ?? DesktopOptions()
        customDock = try container.decodeIfPresent(CustomDockOptions.self, forKey: .customDock) ?? CustomDockOptions()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

extension DockAppearance {
    private enum CodingKeys: String, CodingKey {
        case enabled, orientation, tileSize, magnification, largeSize, autohide, showRecents, minimizeIntoIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DockAppearance()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        orientation = try container.decodeIfPresent(DockOrientation.self, forKey: .orientation) ?? defaults.orientation
        tileSize = try container.decodeIfPresent(Double.self, forKey: .tileSize) ?? defaults.tileSize
        magnification = try container.decodeIfPresent(Bool.self, forKey: .magnification) ?? defaults.magnification
        largeSize = try container.decodeIfPresent(Double.self, forKey: .largeSize) ?? defaults.largeSize
        autohide = try container.decodeIfPresent(Bool.self, forKey: .autohide) ?? defaults.autohide
        showRecents = try container.decodeIfPresent(Bool.self, forKey: .showRecents) ?? defaults.showRecents
        minimizeIntoIcon = try container.decodeIfPresent(Bool.self, forKey: .minimizeIntoIcon) ?? defaults.minimizeIntoIcon
    }
}

extension DesktopOptions {
    private enum CodingKeys: String, CodingKey { case setsWallpaper, wallpaperPath, wallpaperAllScreens }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DesktopOptions()
        setsWallpaper = try container.decodeIfPresent(Bool.self, forKey: .setsWallpaper) ?? defaults.setsWallpaper
        wallpaperPath = try container.decodeIfPresent(String.self, forKey: .wallpaperPath)
        wallpaperAllScreens = try container.decodeIfPresent(Bool.self, forKey: .wallpaperAllScreens) ?? defaults.wallpaperAllScreens
    }
}

/// SF Symbols offered as profile glyphs.
enum ProfileSymbol {
    static let all = [
        "square.grid.2x2", "hammer", "chevron.left.forwardslash.chevron.right",
        "paintbrush", "briefcase", "house", "gamecontroller", "music.note",
        "camera", "video", "chart.bar", "book", "graduationcap", "airplane",
        "cup.and.saucer", "moon.stars", "bolt", "sparkles",
    ]
}
