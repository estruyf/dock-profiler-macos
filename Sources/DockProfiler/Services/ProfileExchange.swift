import AppKit
import Foundation
import UniformTypeIdentifiers

/// Profiles written out to share — a `.dockprofile` file, which is JSON — and
/// read back in, here or on another Mac.
///
/// Going out, paths under the home folder become `~/…` and the bookmarks and
/// modification dates the Dock keeps in each tile are left behind, since they
/// only mean anything to the Mac that made them. Coming in, the paths are put
/// back, an app that lives somewhere else here is found by its bundle
/// identifier, and a wallpaper that is not here is left switched off with its
/// path kept, so it is plain what was meant. Everything gets a fresh id, so a
/// file can be imported twice without the copies sharing one.
enum ProfileExchange {
    static let typeIdentifier = "dev.eliostruyf.DockProfiler.profile"
    static let pathExtension = "dockprofile"
    static let contentType = UTType(exportedAs: typeIdentifier, conformingTo: .json)

    /// What a `.dockprofile` holds. `version` is bumped when a file written by a
    /// newer build would not read here.
    struct File: Codable {
        var format = "dock-profiler"
        var version = 1
        var exportedAt = Date()
        var exportedBy: String?
        var profiles: [DockProfile]
    }

    static let currentVersion = 1

    enum Failure: LocalizedError {
        case notAProfile(String)
        case newer(Int)
        case unreadable(String, Error)

        var errorDescription: String? {
            switch self {
            case .notAProfile(let name):
                return "“\(name)” is not a Dock Profiler profile."
            case .newer:
                return "This profile was exported by a newer version of Dock Profiler."
            case .unreadable(let name, let error):
                return "Could not read “\(name)”: \(error.localizedDescription)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .notAProfile: return "Profiles are .dockprofile files, exported from the profile's menu."
            case .newer: return "Update Dock Profiler and try again."
            case .unreadable: return nil
            }
        }
    }

    // MARK: - Writing

    static func data(for profiles: [DockProfile]) throws -> Data {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let file = File(exportedBy: version.map { "Dock Profiler \($0)" }, profiles: profiles.map { $0.portable() })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    // MARK: - Reading

    static func profiles(in url: URL) throws -> [DockProfile] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Failure.unreadable(url.lastPathComponent, error)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: File
        do {
            file = try decoder.decode(File.self, from: data)
        } catch {
            throw Failure.notAProfile(url.lastPathComponent)
        }
        guard file.format == "dock-profiler" else { throw Failure.notAProfile(url.lastPathComponent) }
        guard file.version <= currentVersion else { throw Failure.newer(file.version) }
        return file.profiles.map { $0.localized() }
    }

    // MARK: - Paths

    private static let home = NSHomeDirectory()

    /// `/Users/you/Downloads` → `~/Downloads`, so it lands in the right place on another Mac.
    static func portablePath(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func localPath(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }
}

// MARK: - Making a profile portable, and local again

extension DockProfile {
    /// The profile as it goes into a file: no ids or dates that would clash on
    /// import, and every path relative to the home folder.
    func portable() -> DockProfile {
        var profile = self
        profile.apps = apps.map { $0.portable() }
        profile.others = others.map { $0.portable() }
        profile.desktop.wallpaperPath = desktop.wallpaperPath.map(ProfileExchange.portablePath)
        profile.customDock.widgets = customDock.widgets.map { widget in
            var widget = widget
            widget.path = widget.path.map(ProfileExchange.portablePath)
            widget.apps = widget.apps.map { $0.portable() }
            widget.anchor = widget.anchor.mapped(ProfileExchange.portablePath)
            return widget
        }
        // Positions keyed by display id are kept: a profile shared between your own
        // Macs on the same displays wants them, and anyone else's displays ignore them.
        return profile
    }

    /// The profile as it comes out of a file: paths expanded, apps found where they
    /// are on this Mac, fresh ids all round.
    func localized() -> DockProfile {
        var profile = self
        profile.id = UUID()
        profile.createdAt = Date()
        profile.updatedAt = Date()

        // An app that has moved — /Applications here, ~/Applications there — takes
        // its local path, and any widget anchored to it follows.
        var moved: [String: String] = [:]
        profile.apps = apps.map { tile in
            let local = tile.localized()
            if let from = tile.path.map(ProfileExchange.localPath), let to = local.path, from != to {
                moved[from] = to
            }
            return local
        }
        profile.others = others.map { $0.localized() }
        profile.customDock.widgets = customDock.widgets.map { widget in
            var widget = widget
            widget.id = UUID()
            widget.path = widget.path.map(ProfileExchange.localPath)
            widget.apps = widget.apps.map { $0.localized() }
            widget.anchor = widget.anchor.mapped { path in
                let local = ProfileExchange.localPath(path)
                return moved[local] ?? local
            }
            return widget
        }

        if let path = desktop.wallpaperPath.map(ProfileExchange.localPath) {
            profile.desktop.wallpaperPath = path
            if !FileManager.default.fileExists(atPath: path) {
                profile.desktop.setsWallpaper = false
            }
        }
        return profile
    }
}

extension WidgetAnchor {
    /// The anchor with its app path passed through `transform`.
    func mapped(_ transform: (String) -> String) -> WidgetAnchor {
        switch self {
        case .start, .end: return self
        case .after(let path): return .after(transform(path))
        case .afterSpacers(let path, let count): return .afterSpacers(path.map(transform), count)
        }
    }
}

extension DockTile {
    /// The keys the Dock keeps for its own Mac: a bookmark to the file and the
    /// dates it last saw it. The Dock makes them again from the path.
    private static let machineKeys = ["book", "file-mod-date", "parent-mod-date"]

    /// The tile with its path relative to the home folder and without the Dock's
    /// per-Mac bookkeeping.
    func portable() -> DockTile {
        var tile = self
        tile.path = path.map(ProfileExchange.portablePath)
        tile.raw = rewritingRaw { tileData in
            for key in Self.machineKeys { tileData.removeValue(forKey: key) }
            if var fileData = tileData["file-data"] as? [String: Any] {
                fileData.removeValue(forKey: "_CFURLAliasData")
                if let string = fileData["_CFURLString"] as? String, let url = URL(string: string), url.isFileURL {
                    fileData["_CFURLString"] = ProfileExchange.portablePath(url.path)
                }
                tileData["file-data"] = fileData
            }
        }
        return tile
    }

    /// The tile as it is on this Mac: the path expanded and turned back into the
    /// URL the Dock expects — or, for an app that is not there but is installed
    /// somewhere else here, the local copy.
    func localized() -> DockTile {
        if kind == .app, let path = path.map(ProfileExchange.localPath),
           !FileManager.default.fileExists(atPath: path),
           let identifier = bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           let found = DockTile.app(at: url) {
            return found
        }
        var tile = self
        tile.id = UUID()
        tile.path = path.map(ProfileExchange.localPath)
        tile.raw = rewritingRaw { tileData in
            guard var fileData = tileData["file-data"] as? [String: Any],
                  let string = fileData["_CFURLString"] as? String,
                  string.hasPrefix("~") || string.hasPrefix("/") else { return }
            let local = ProfileExchange.localPath(string)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: local, isDirectory: &isDirectory)
            let directory = exists ? isDirectory.boolValue : (kind == .app || kind == .folder)
            fileData["_CFURLString"] = URL(fileURLWithPath: local, isDirectory: directory).absoluteString
            tileData["file-data"] = fileData
        }
        return tile
    }

    /// `raw` with its `tile-data` dictionary edited in place; unchanged if it
    /// cannot be read or written.
    private func rewritingRaw(_ edit: (inout [String: Any]) -> Void) -> Data {
        guard var dictionary = (try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)) as? [String: Any] else {
            return raw
        }
        var tileData = dictionary["tile-data"] as? [String: Any] ?? [:]
        edit(&tileData)
        dictionary["tile-data"] = tileData
        return (try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)) ?? raw
    }
}

// MARK: - Panels

/// The user-facing half: the save and open panels, and what happens to what
/// they choose.
@MainActor
enum ProfileSharing {
    /// Asks where to save the profiles and writes them there. One profile is
    /// named after itself; several, after the app.
    static func export(_ profiles: [DockProfile]) {
        guard !profiles.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [ProfileExchange.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = (profiles.count == 1 ? profiles[0].name : "Dock Profiler profiles") + "." + ProfileExchange.pathExtension
        panel.title = profiles.count == 1 ? "Export “\(profiles[0].name)”" : "Export Profiles"
        panel.prompt = "Export"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileExchange.data(for: profiles).write(to: url, options: .atomic)
        } catch {
            present(error)
        }
    }

    /// Asks for files to import and adds what is in them.
    static func importFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [ProfileExchange.contentType, .json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Import Profiles"
        panel.prompt = "Import"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        importProfiles(from: panel.urls)
    }

    /// Adds the profiles in the files to the store and opens the manager on the
    /// last of them. Files that cannot be read are reported, and the rest still
    /// go in.
    static func importProfiles(from urls: [URL]) {
        var added: [DockProfile] = []
        var failures: [Error] = []
        for url in urls {
            do {
                added += ProfileStore.shared.add(try ProfileExchange.profiles(in: url))
            } catch {
                failures.append(error)
            }
        }
        if let last = added.last {
            ManagerWindowController.shared.show(selecting: last.id)
        }
        for error in failures { present(error) }
    }

    /// Whether a dropped or opened file is one of ours.
    static func isProfileFile(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == ProfileExchange.pathExtension
    }

    private static func present(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.localizedDescription
        if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
            alert.informativeText = suggestion
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
