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
    ///
    /// A browser profile that already has a window up comes forward instead, as
    /// the profile's own taskbar button would bring it on Windows: its front
    /// window is raised — back off the Dock when they are all minimized — and
    /// no new one is opened.
    @MainActor
    static func open(_ tile: WidgetTile) {
        guard let url = tile.appURL, FileManager.default.fileExists(atPath: url.path) else { return }
        if let profile = tile.browserProfile, let identifier = Bundle(url: url)?.bundleIdentifier {
            let windows = BrowserProfiles.windows(of: profile.id, of: identifier)
            if let window = windows.first(where: { !$0.isMinimized }) ?? windows.first {
                window.raise()
                return
            }
            // Up, but its windows out of reach — without Accessibility, or a
            // browser that names them some other way: the browser comes forward
            // as a whole, which is still better than another window.
            if BrowserProfileMonitor.shared.isOpen(profile.id, of: identifier),
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { !$0.isTerminated }) {
                AppWindows.activate(app)
                return
            }
        }
        if let app = instance(of: tile) {
            bringForward(app)
            return
        }
        let arguments = arguments(of: tile)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = !arguments.isEmpty
        if arguments.isEmpty, let identifier = Bundle(url: url)?.bundleIdentifier {
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { !$0.isTerminated }?.unhide()
        }
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: - The launcher's own copy

    /// The copy of the app this launcher started, while it runs: a running
    /// instance whose command line carries the tile's arguments. An app that
    /// runs as several instances — Claude with a second `--user-data-dir` — can
    /// then be told apart from the copy opened the usual way, and so gets its
    /// own running dot and is brought forward rather than started again. An app
    /// that keeps to one instance hands the arguments over and quits, so there
    /// is never a copy to find and each click still opens a window. Browser
    /// profiles have their own way of knowing, and a launcher without arguments
    /// is the app itself.
    @MainActor
    static func instance(of tile: WidgetTile) -> NSRunningApplication? {
        guard tile.browserProfile == nil,
              let identifier = tile.appURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }) else { return nil }
        let wanted = arguments(of: tile)
        guard !wanted.isEmpty else { return nil }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { !$0.isTerminated }
        return apps.first { app in
            guard let line = commandLine(of: app.processIdentifier) else { return false }
            // The executable's path and argv[0] come first; macOS may add its own after ours.
            let given = Array(line.dropFirst(2))
            guard given.count >= wanted.count else { return false }
            return (0...(given.count - wanted.count)).contains { Array(given[$0..<$0 + wanted.count]) == wanted }
        }
    }

    /// What Quit on the launcher's menu quits: its own copy, or with no arguments
    /// the app, as an app tile's Quit does. Nothing for a browser profile — the
    /// browser is one process for all its profiles, so quitting it would close
    /// the others too.
    @MainActor
    static func quittable(_ tile: WidgetTile) -> [NSRunningApplication] {
        guard tile.browserProfile == nil else { return [] }
        if let app = instance(of: tile) { return [app] }
        guard arguments(of: tile).isEmpty,
              let identifier = tile.appURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }) else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { !$0.isTerminated }
    }

    /// Command lines by process, since a process's never changes and the dot
    /// asks on every redraw. Processes that have gone are dropped as they are
    /// noticed, so a reused process id is read afresh.
    @MainActor private static var commandLines: [pid_t: [String]] = [:]

    @MainActor
    private static func commandLine(of pid: pid_t) -> [String]? {
        if let known = commandLines[pid] { return known }
        let live = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        commandLines = commandLines.filter { live.contains($0.key) }
        guard let line = ProcessArgumentReader()?.arguments(of: pid) else { return nil }
        commandLines[pid] = line
        return line
    }

    /// Brings the launcher's copy forward — that instance, not whichever one
    /// Launch Services would pick. With no window of its own on screen — closed,
    /// or minimized — it is also sent the reopen event a click on its Dock icon
    /// sends, which puts a window back. That is an Apple Event, so macOS may ask
    /// once whether Dock Profiler may control the app; it is sent off the main
    /// thread so the question never holds up the dock.
    @MainActor
    private static func bringForward(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        app.activate()
        guard !hasWindowOnScreen(app.processIdentifier) else { return }
        let pid = app.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEReopenApplication),
                targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
            _ = try? event.sendEvent(options: .noReply, timeout: 5)
        }
    }

    /// Whether the process has an ordinary window on screen. The window list's
    /// owners and layers need no permission; only titles would.
    private static func hasWindowOnScreen(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
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
    /// when it has one; else the profile's initial on its colour — or, when the
    /// tile asks for it and the browser has one saved, the account's picture.
    /// Nil for a launcher with neither letters nor a profile.
    static func badgeImage(of tile: WidgetTile, side: CGFloat) -> NSImage? {
        let profile = tile.browserProfile.flatMap { chosen in
            tile.appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
                .flatMap { BrowserProfiles.profiles(of: $0, side: side).first { $0.id == chosen.id } }
        }
        if let badge = badgeText(of: tile) {
            return BrowserProfiles.monogram(badge, on: profile?.color ?? .systemGray, side: side)
        }
        guard let profile else { return nil }
        if tile.showsProfilePicture, let picture = profile.picture { return picture }
        return BrowserProfiles.monogram(profile.initial, on: profile.color, side: side)
    }

    /// The badge as typed, trimmed to its first two characters; nil when blank.
    static func badgeText(of tile: WidgetTile) -> String? {
        let text = (tile.badge ?? "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(2))
    }
}
