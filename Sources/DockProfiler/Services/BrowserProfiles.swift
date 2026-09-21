import AppKit

/// One of a browser's profiles — a Chrome "person", a Firefox profile — as the
/// browser's own profile menu lists it.
struct BrowserProfile: Identifiable {
    /// What the browser is told to open: Chromium's profile directory, Firefox's profile name.
    let id: String
    let name: String
    /// A window of this profile is up right now. Chromium keeps the list; Firefox
    /// does not say, so its profiles are never marked.
    let isOpen: Bool
    /// The account's picture, or the initial on the profile's colour, at menu size.
    let image: NSImage?
    /// The profile's own colour, for a badge drawn in its place.
    let color: NSColor
}

/// The profiles of the browsers on the dock, read from the files the browsers
/// keep them in — Chromium's `Local State`, Firefox's `profiles.ini` — so a
/// tile's menu can open a window as one of them, the way the browsers' own Dock
/// menus do. Read afresh on every menu, so a profile made a moment ago is there.
enum BrowserProfiles {
    /// The browsers whose profiles can be read, by bundle identifier, and where
    /// under `~/Library/Application Support` each keeps them. Arc is left out: its
    /// profiles belong to spaces, and a launch cannot pick one.
    private enum Family {
        case chromium(String)
        case firefox(String)
    }

    private static let families: [String: Family] = [
        "com.google.Chrome": .chromium("Google/Chrome"),
        "com.google.Chrome.beta": .chromium("Google/Chrome Beta"),
        "com.google.Chrome.dev": .chromium("Google/Chrome Dev"),
        "com.google.Chrome.canary": .chromium("Google/Chrome Canary"),
        "com.microsoft.edgemac": .chromium("Microsoft Edge"),
        "com.microsoft.edgemac.Beta": .chromium("Microsoft Edge Beta"),
        "com.microsoft.edgemac.Dev": .chromium("Microsoft Edge Dev"),
        "com.microsoft.edgemac.Canary": .chromium("Microsoft Edge Canary"),
        "com.brave.Browser": .chromium("BraveSoftware/Brave-Browser"),
        "com.brave.Browser.beta": .chromium("BraveSoftware/Brave-Browser-Beta"),
        "com.brave.Browser.nightly": .chromium("BraveSoftware/Brave-Browser-Nightly"),
        "com.vivaldi.Vivaldi": .chromium("Vivaldi"),
        "org.chromium.Chromium": .chromium("Chromium"),
        "org.mozilla.firefox": .firefox("Firefox"),
        "org.mozilla.firefoxdeveloperedition": .firefox("Firefox"),
        "org.mozilla.nightly": .firefox("Firefox"),
        "app.zen-browser.zen": .firefox("zen"),
    ]

    private static let supportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// Whether the app is a browser whose profiles are known how to read.
    static func isBrowser(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { families[$0] != nil } ?? false
    }

    /// The browser's profiles in the order its picker shows them, their pictures
    /// `side` points across; empty when the browser is not one that is known, or
    /// has not been run.
    static func profiles(of bundleIdentifier: String, side: CGFloat = menuSide) -> [BrowserProfile] {
        switch families[bundleIdentifier] {
        case .chromium(let directory):
            return chromiumProfiles(in: supportDirectory.appendingPathComponent(directory), running: isRunning(bundleIdentifier), side: side)
        case .firefox(let directory):
            return firefoxProfiles(in: supportDirectory.appendingPathComponent(directory), side: side)
        case nil:
            return []
        }
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }

    /// Opens a new window of the browser as the profile: a fresh process with the
    /// browser's own switch, which a running browser takes over and answers with
    /// a window, as `open -na` would.
    ///
    /// Firefox only listens to `-P` when no Firefox is running, so with one up the
    /// new process is told to stand on its own; opening the profile that is
    /// already running then gets Firefox's own "already running" notice, which
    /// is what its profile manager does too.
    static func open(_ profile: BrowserProfile, of bundleIdentifier: String, at url: URL) {
        guard let arguments = arguments(opening: profile.id, of: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// The browser's own switch for opening as the profile, for a fresh process
    /// of it; nil for a browser that is not known.
    static func arguments(opening profileID: String, of bundleIdentifier: String) -> [String]? {
        switch families[bundleIdentifier] {
        case .chromium:
            return ["--profile-directory=\(profileID)"]
        case .firefox:
            return ["-P", profileID] + (isRunning(bundleIdentifier) ? ["-no-remote"] : [])
        case nil:
            return nil
        }
    }

    // MARK: - Chromium

    /// `Local State` holds every profile under `profile.info_cache`, keyed by its
    /// directory, with the picker's order in `profiles_order` and the ones with
    /// windows up in `last_active_profiles` — which stays after the browser quits,
    /// for it to restore, so it only counts while the browser runs.
    private static func chromiumProfiles(in directory: URL, running: Bool, side: CGFloat) -> [BrowserProfile] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = state["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        let order = profile["profiles_order"] as? [String] ?? []
        let open = running ? Set(profile["last_active_profiles"] as? [String] ?? []) : []
        // The picker's order first, then any it does not know, by name.
        let rest = cache.keys.filter { !order.contains($0) }
            .sorted { chromiumName(cache[$0]!).localizedCaseInsensitiveCompare(chromiumName(cache[$1]!)) == .orderedAscending }
        return (order.filter { cache[$0] != nil } + rest).map { key in
            let info = cache[key]!
            let color = (info["profile_highlight_color"] as? Int).map(skColor) ?? .systemGray
            return BrowserProfile(
                id: key,
                name: chromiumName(info),
                isOpen: open.contains(key),
                image: chromiumImage(for: info, in: directory.appendingPathComponent(key), color: color, side: side),
                color: color
            )
        }
    }

    /// The name the browser shows: the one given to the profile, or the account's
    /// when the profile was never named.
    private static func chromiumName(_ info: [String: Any]) -> String {
        let name = info["name"] as? String ?? ""
        let account = info["gaia_name"] as? String ?? ""
        if info["is_using_default_name"] as? Bool == true, !account.isEmpty { return account }
        return name.isEmpty ? (account.isEmpty ? "Profile" : account) : name
    }

    /// The account's picture where the browser saved it, else the profile's
    /// initial on its colour — the fallback the browsers draw themselves.
    private static func chromiumImage(for info: [String: Any], in directory: URL, color: NSColor, side: CGFloat) -> NSImage? {
        let names = [info["gaia_picture_file_name"] as? String, "Google Profile Picture.png", "Edge Profile Picture.png"]
        for name in names.compactMap({ $0 }) {
            let url = directory.appendingPathComponent(name)
            if let image = cachedPicture(at: url, side: side) { return image }
        }
        return monogram(String(chromiumName(info).prefix(1)).uppercased(), on: color, side: side)
    }

    /// Chromium's SkColor: ARGB in a signed 32-bit integer.
    private static func skColor(_ value: Int) -> NSColor {
        let bits = UInt32(truncatingIfNeeded: value)
        return NSColor(
            red: CGFloat((bits >> 16) & 0xff) / 255,
            green: CGFloat((bits >> 8) & 0xff) / 255,
            blue: CGFloat(bits & 0xff) / 255,
            alpha: 1
        )
    }

    // MARK: - Firefox

    /// `profiles.ini` has a `[ProfileN]` section per profile with its `Name`.
    /// The order is the file's, which is the profile manager's.
    private static func firefoxProfiles(in directory: URL, side: CGFloat) -> [BrowserProfile] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("profiles.ini"), encoding: .utf8) else {
            return []
        }
        var profiles: [BrowserProfile] = []
        var inProfile = false
        var name: String?
        func flush() {
            if inProfile, let name, !name.isEmpty {
                profiles.append(BrowserProfile(
                    id: name, name: name, isOpen: false,
                    image: monogram(String(name.prefix(1)).uppercased(), on: .systemGray, side: side),
                    color: .systemGray
                ))
            }
            name = nil
        }
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                inProfile = line.hasPrefix("[Profile")
            } else if inProfile, line.hasPrefix("Name=") {
                name = String(line.dropFirst("Name=".count))
            }
        }
        flush()
        return profiles
    }

    // MARK: - Pictures

    /// The size a menu item's image is drawn at.
    static let menuSide: CGFloat = 16

    /// Pictures are big — a megabyte each — so each is read once per version, at each size asked for.
    private static var pictures: [String: (modified: Date, image: NSImage)] = [:]

    private static func cachedPicture(at url: URL, side: CGFloat) -> NSImage? {
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return nil
        }
        let key = "\(url.path)@\(side)"
        if let cached = pictures[key], cached.modified == modified { return cached.image }
        guard let picture = NSImage(contentsOf: url) else { return nil }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        pictures[key] = (modified, image)
        return image
    }

    /// A letter — or two, drawn smaller — on a disc, as the browsers draw a
    /// profile without a picture.
    static func monogram(_ letters: String, on color: NSColor, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            // White on a dark colour, near-black on a light one.
            let luminance = color.usingColorSpace(.sRGB).map { 0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent } ?? 0
            let text = NSAttributedString(string: letters, attributes: [
                .font: NSFont.systemFont(ofSize: side * (letters.count > 1 ? 0.42 : 0.6), weight: .semibold),
                .foregroundColor: luminance > 0.6 ? NSColor.black.withAlphaComponent(0.75) : NSColor.white,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
    }
}
