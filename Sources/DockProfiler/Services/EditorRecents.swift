import AppKit

/// One entry from an editor's Open Recent list: a project folder, or a
/// multi-root workspace file.
struct EditorRecent: Identifiable {
    enum Kind {
        case folder
        case workspace
    }

    let url: URL
    let kind: Kind
    /// The path the way the editor writes it in its own menu, `~` for the home
    /// folder — what the menu item's tooltip shows.
    let path: String

    var id: String { url.path }

    /// What the menu item is called: the folder's own name, a workspace's
    /// without the `.code-workspace` on the end, since the dock's menu has no
    /// room for a path.
    var name: String {
        switch kind {
        case .folder: return url.lastPathComponent
        case .workspace: return url.deletingPathExtension().lastPathComponent
        }
    }

    /// The folder's or workspace file's own icon, at the size a menu draws one.
    var image: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: EditorRecents.menuSide, height: EditorRecents.menuSide)
        return icon
    }
}

/// The recent projects of the editors on the dock, read from the file the
/// editor keeps its menu bar in, so a tile's menu can reopen one the way the
/// editor's own File ▸ Open Recent does. Read afresh on every menu, so a folder
/// opened a moment ago is at the top.
enum EditorRecents {
    /// The editors whose recent list can be read, by bundle identifier, and the
    /// folder each keeps its state in under `~/Library/Application Support`.
    private static let editors: [String: String] = [
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
    ]

    private static let supportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// The size a menu item's image is drawn at.
    static let menuSide: CGFloat = 16

    /// Whether the app is an editor whose recent projects are known how to read.
    static func isEditor(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { editors[$0] != nil } ?? false
    }

    /// The editor's recent projects, newest first, at most `limit` of them:
    /// the folders and workspaces of its Open Recent menu that are still on this
    /// Mac. Empty when the editor is not one that is known, has not been run, or
    /// has nothing but files and remote folders in its list.
    static func projects(of bundleIdentifier: String, limit: Int = 10) -> [EditorRecent] {
        guard let directory = editors[bundleIdentifier] else { return [] }
        let url = supportDirectory
            .appendingPathComponent(directory)
            .appendingPathComponent("User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: url),
              let storage = try? JSONDecoder().decode(Storage.self, from: data),
              let file = storage.lastKnownMenubarData?.menus["File"],
              let items = file.items.first(where: { $0.id == recentMenu })?.submenu?.items else { return [] }
        var projects: [EditorRecent] = []
        var seen: Set<String> = []
        for item in items {
            guard let kind = kinds[item.id ?? ""] else { continue }
            // Only what this Mac can open: a folder on a remote or a container
            // comes with a `vscode-remote` scheme, and needs the editor's own
            // window to reach it.
            guard item.uri?.scheme == "file", let path = item.uri?.path else { continue }
            let url = URL(fileURLWithPath: path)
            guard !seen.contains(url.path), FileManager.default.fileExists(atPath: url.path) else { continue }
            seen.insert(url.path)
            projects.append(EditorRecent(url: url, kind: kind, path: item.label ?? (url.path as NSString).abbreviatingWithTildeInPath))
            if projects.count == limit { break }
        }
        return projects
    }

    /// Opens the project in the editor, as choosing it from Open Recent would:
    /// a running editor takes the folder over and answers with a window, since
    /// it keeps to one process.
    static func open(_ project: EditorRecent, in editor: URL) {
        NSWorkspace.shared.open([project.url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - The editor's menu bar on disk

    /// VS Code writes the menu bar it last drew — Open Recent filled in — to
    /// `storage.json`, where the list can be read without asking the editor for
    /// it. Its own `recently.opened` is the older, half-kept copy.
    private struct Storage: Decodable {
        let lastKnownMenubarData: Menubar?

        struct Menubar: Decodable {
            let menus: [String: Menu]
        }

        struct Menu: Decodable {
            let items: [Item]
        }

        struct Item: Decodable {
            let id: String?
            let label: String?
            let uri: URI?
            let submenu: Menu?
        }

        struct URI: Decodable {
            let scheme: String?
            let path: String?
        }
    }

    /// The File menu's Open Recent submenu, and the entries in it that are a
    /// project rather than a single file.
    private static let recentMenu = "submenuitem.MenubarRecentMenu"

    private static let kinds: [String: EditorRecent.Kind] = [
        "openRecentFolder": .folder,
        "openRecentWorkspace": .workspace,
    ]
}
