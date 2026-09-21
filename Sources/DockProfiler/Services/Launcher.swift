import AppKit

/// Opens a Launcher widget's app the way its tile says: a fresh process with the
/// arguments written on its card — and, for a browser, the switch that opens it
/// as the chosen profile — as `open -na App --args …` would.
enum Launcher {
    /// What the app is started with: the profile's switch first, then the
    /// arguments as typed, split the way a shell splits them.
    static func arguments(of tile: WidgetTile) -> [String] {
        var arguments: [String] = []
        if let profile = tile.browserProfile,
           let identifier = tile.appURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }),
           let switches = BrowserProfiles.arguments(opening: profile.id, of: identifier) {
            arguments += switches
        }
        return arguments + split(tile.arguments)
    }

    /// A launcher with nothing to pass behaves as an app tile: it brings a
    /// running app forward — sending the reopen event that puts a window back —
    /// rather than starting a second copy. With arguments there has to be a new
    /// process, since a running app is never handed them; apps that keep to one
    /// instance — the browsers, VS Code — take it over and answer with a window.
    static func open(_ tile: WidgetTile) {
        guard let url = tile.appURL, FileManager.default.fileExists(atPath: url.path) else { return }
        let arguments = arguments(of: tile)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = !arguments.isEmpty
        if arguments.isEmpty, let identifier = Bundle(url: url)?.bundleIdentifier {
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { !$0.isTerminated }?.unhide()
        }
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Splits a line into arguments as a shell would: on whitespace, keeping what
    /// is inside single or double quotes together, a backslash escaping the next
    /// character. A leading `~/` is the home folder, so a path can be written the
    /// way it is typed.
    static func split(_ line: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var inArgument = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
                inArgument = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inArgument = true
            } else if character.isWhitespace {
                if inArgument { arguments.append(expandingTilde(current)) }
                current = ""
                inArgument = false
            } else {
                current.append(character)
                inArgument = true
            }
        }
        if inArgument { arguments.append(expandingTilde(current)) }
        return arguments
    }

    private static func expandingTilde(_ argument: String) -> String {
        guard argument == "~" || argument.hasPrefix("~/") else { return argument }
        return (argument as NSString).expandingTildeInPath
    }

    // MARK: - Icons

    /// The tile's own icon: an image file as it is, or another app's icon — an
    /// `.app` dropped on the card. Nil when the launcher has none, or the file has gone.
    static func customIcon(of tile: WidgetTile) -> NSImage? {
        guard let path = tile.iconPath, FileManager.default.fileExists(atPath: path) else { return nil }
        if path.hasSuffix(".app") {
            return NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        }
        return NSImage(contentsOfFile: path)
    }

    /// The app's own icon, or nil when the app has gone.
    static func appIcon(of tile: WidgetTile) -> NSImage? {
        guard let path = tile.path, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    /// The badge on the app's icon: the tile's own letters, on the profile's colour
    /// when it has one; else the profile's picture — the account's, or its initial
    /// on its colour. Nil for a launcher with neither.
    static func badgeImage(of tile: WidgetTile, side: CGFloat) -> NSImage? {
        let profile = tile.browserProfile.flatMap { chosen in
            tile.appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
                .flatMap { BrowserProfiles.profiles(of: $0, side: side).first { $0.id == chosen.id } }
        }
        if let badge = badgeText(of: tile) {
            return BrowserProfiles.monogram(badge, on: profile?.color ?? .systemGray, side: side)
        }
        return profile?.image
    }

    /// The icon as the tile draws it, in one image for a stack or a menu: its own
    /// icon, or the app's with the badge on its corner. Nil when the app has gone
    /// and there is no icon of its own.
    static func icon(of tile: WidgetTile, side: CGFloat) -> NSImage? {
        if let custom = customIcon(of: tile) { return custom }
        guard let app = appIcon(of: tile) else { return nil }
        guard let badge = badgeImage(of: tile, side: side * 0.42) else { return app }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            app.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            let badgeSide = side * 0.42
            let badgeRect = NSRect(x: rect.maxX - badgeSide + badgeSide * 0.12, y: rect.minY - badgeSide * 0.12, width: badgeSide, height: badgeSide)
            badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// The badge as typed, trimmed to its first two characters; nil when blank.
    static func badgeText(of tile: WidgetTile) -> String? {
        let text = (tile.badge ?? "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(2))
    }
}
