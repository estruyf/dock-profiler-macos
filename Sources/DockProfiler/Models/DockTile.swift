import AppKit
import Foundation

/// The two independent halves of the Dock's pinned content.
enum DockSection: String, Codable, Hashable, CaseIterable, Identifiable {
    case apps
    case others

    var id: String { rawValue }

    var preferenceKey: String {
        switch self {
        case .apps: return "persistent-apps"
        case .others: return "persistent-others"
        }
    }

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .others: return "Folders & Files"
        }
    }
}

enum DockTileKind: String, Codable, Hashable {
    case app
    case folder
    case url
    case spacer
    case smallSpacer
    case flexSpacer
    case other

    var tileType: String {
        switch self {
        case .app, .other: return "file-tile"
        case .folder: return "directory-tile"
        case .url: return "url-tile"
        case .spacer: return "spacer-tile"
        case .smallSpacer: return "small-spacer-tile"
        case .flexSpacer: return "flex-spacer-tile"
        }
    }

    static func from(tileType: String) -> DockTileKind {
        switch tileType {
        case "file-tile": return .app
        case "directory-tile": return .folder
        case "url-tile": return .url
        case "spacer-tile": return .spacer
        case "small-spacer-tile": return .smallSpacer
        case "flex-spacer-tile": return .flexSpacer
        default: return .other
        }
    }

    var isSpacer: Bool {
        self == .spacer || self == .smallSpacer || self == .flexSpacer
    }

    var defaultLabel: String {
        switch self {
        case .spacer: return "Spacer"
        case .smallSpacer: return "Small spacer"
        case .flexSpacer: return "Flexible spacer"
        default: return "Item"
        }
    }

    var symbolName: String {
        switch self {
        case .app: return "app.dashed"
        case .folder: return "folder"
        case .url: return "link"
        case .spacer, .smallSpacer, .flexSpacer: return "arrow.left.and.right"
        case .other: return "questionmark.square.dashed"
        }
    }
}

/// One pinned item in the Dock.
///
/// The full tile dictionary the Dock itself uses is kept verbatim in `raw`, so a
/// captured Dock round-trips exactly (bookmarks, mod dates, `dock-extra`, …).
/// The other fields are just what the UI needs to render a row.
struct DockTile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: DockTileKind
    var label: String
    var bundleIdentifier: String?
    var path: String?
    var raw: Data

    // MARK: - Reading

    init?(dictionary: [String: Any]) {
        let tileType = dictionary["tile-type"] as? String ?? "file-tile"
        let kind = DockTileKind.from(tileType: tileType)
        let tileData = dictionary["tile-data"] as? [String: Any] ?? [:]

        self.kind = kind
        self.bundleIdentifier = tileData["bundle-identifier"] as? String
        self.path = Self.path(fromTileData: tileData)

        if kind.isSpacer {
            self.label = kind.defaultLabel
        } else if let label = tileData["file-label"] as? String {
            self.label = label
        } else if let label = tileData["label"] as? String {
            self.label = label
        } else if let path = self.path {
            self.label = (path as NSString).lastPathComponent
        } else {
            self.label = "Untitled"
        }

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dictionary, format: .binary, options: 0
        ) else { return nil }
        self.raw = data
    }

    private static func path(fromTileData tileData: [String: Any]) -> String? {
        guard let fileData = tileData["file-data"] as? [String: Any],
              let string = fileData["_CFURLString"] as? String else { return nil }
        if let url = URL(string: string), url.isFileURL { return url.path }
        return string.removingPercentEncoding
    }

    /// The dictionary handed back to the Dock. A fresh GUID is generated so the
    /// Dock never sees two tiles claiming the same identity.
    func dockDictionary() -> [String: Any] {
        var dictionary = (try? PropertyListSerialization.propertyList(
            from: raw, options: [], format: nil
        )) as? [String: Any] ?? [:]
        dictionary["tile-type"] = kind.tileType
        dictionary["GUID"] = Int(UInt32.random(in: 1_000_000...4_294_967_294))
        if dictionary["tile-data"] == nil { dictionary["tile-data"] = [String: Any]() }
        return dictionary
    }

    // MARK: - Creating

    static func app(at url: URL) -> DockTile? {
        let bundle = Bundle(url: url)
        let label = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        var tileData: [String: Any] = [
            "file-data": [
                "_CFURLString": url.absoluteString,
                "_CFURLStringType": 15,
            ],
            "file-label": label,
            "file-type": 41,
            "dock-extra": false,
        ]
        if let identifier = bundle?.bundleIdentifier {
            tileData["bundle-identifier"] = identifier
        }
        return DockTile(dictionary: ["tile-data": tileData, "tile-type": "file-tile"])
    }

    static func folder(at url: URL) -> DockTile? {
        let tileData: [String: Any] = [
            "file-data": [
                "_CFURLString": url.absoluteString,
                "_CFURLStringType": 15,
            ],
            "file-label": url.lastPathComponent,
            "file-type": 2,
            "arrangement": 2,      // sort by date added
            "displayas": 0,        // stack
            "showas": 1,           // fan
            "preferreditemsize": -1,
        ]
        return DockTile(dictionary: ["tile-data": tileData, "tile-type": "directory-tile"])
    }

    static func spacer(_ kind: DockTileKind) -> DockTile? {
        DockTile(dictionary: ["tile-data": [String: Any](), "tile-type": kind.tileType])
    }

    // MARK: - Presentation

    var isMissing: Bool {
        guard !kind.isSpacer, let path else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }

    var icon: NSImage? {
        guard !kind.isSpacer else { return nil }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    var subtitle: String {
        if kind.isSpacer { return kind.defaultLabel }
        guard let path else { return bundleIdentifier ?? "" }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
