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

/// The optional desktop half of a profile: jump to a Space and/or set a wallpaper.
struct DesktopOptions: Codable, Hashable {
    var switchesSpace: Bool = false
    var spaceIndex: Int = 1
    var setsWallpaper: Bool = false
    var wallpaperPath: String?
    var wallpaperAllScreens: Bool = true

    var isActive: Bool { switchesSpace || (setsWallpaper && wallpaperPath != nil) }

    var summary: String? {
        var parts: [String] = []
        if switchesSpace { parts.append("Desktop \(spaceIndex)") }
        if setsWallpaper, wallpaperPath != nil {
            parts.append("Wallpaper")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
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
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    func tiles(in section: DockSection) -> [DockTile] {
        section == .apps ? apps : others
    }

    var itemSummary: String {
        let appCount = apps.filter { !$0.kind.isSpacer }.count
        var summary = "\(appCount) app\(appCount == 1 ? "" : "s")"
        if managesOthers, !others.isEmpty {
            summary += " · \(others.count) item\(others.count == 1 ? "" : "s")"
        }
        if let desktop = desktop.summary { summary += " · \(desktop)" }
        return summary
    }

    static func empty(named name: String = "New Profile") -> DockProfile {
        DockProfile(name: name)
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
