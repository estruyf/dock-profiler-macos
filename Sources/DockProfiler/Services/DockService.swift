import AppKit
import Foundation

/// The Dock settings a combined custom dock overrides, kept so they can be put back.
struct DockHideState: Codable, Equatable {
    var autohide: Bool
    /// `autohide-delay`, when the user has one set; nil means the key is absent.
    var autohideDelay: Double?

    /// Auto-hidden with a delay so long the Dock never comes back on its own —
    /// ⌘⌥D still toggles it, and it returns when this state is restored.
    static let parked = DockHideState(autohide: true, autohideDelay: 1_000_000)
}

struct DockSnapshot {
    var apps: [DockTile] = []
    var others: [DockTile] = []
    var appearance: DockAppearance = DockAppearance()
}

enum DockServiceError: LocalizedError {
    case preferencesWriteFailed

    var errorDescription: String? {
        switch self {
        case .preferencesWriteFailed:
            return "Could not write the Dock preferences. Check that Dock Profiler is allowed to control app preferences."
        }
    }
}

/// Reads and writes `com.apple.dock` the same way `defaults` does, then restarts
/// the Dock so it picks the new layout up.
enum DockService {
    static let domain = "com.apple.dock" as CFString

    // MARK: - Reading

    static func snapshot() -> DockSnapshot {
        CFPreferencesAppSynchronize(domain)
        var snapshot = DockSnapshot()
        snapshot.apps = tiles(in: .apps)
        snapshot.others = tiles(in: .others)
        snapshot.appearance = readAppearance()
        return snapshot
    }

    static func tiles(in section: DockSection) -> [DockTile] {
        rawTiles(in: section).compactMap { DockTile(dictionary: $0) }
    }

    static func rawTiles(in section: DockSection) -> [[String: Any]] {
        guard let value = CFPreferencesCopyAppValue(section.preferenceKey as CFString, domain),
              let array = value as? [[String: Any]] else { return [] }
        return array
    }

    private static func value<T>(_ key: String, as type: T.Type) -> T? {
        CFPreferencesCopyAppValue(key as CFString, domain) as? T
    }

    static func readAppearance() -> DockAppearance {
        var appearance = DockAppearance()
        if let orientation = value("orientation", as: String.self),
           let parsed = DockOrientation(rawValue: orientation) {
            appearance.orientation = parsed
        }
        if let size = value("tilesize", as: Double.self) { appearance.tileSize = size }
        if let large = value("largesize", as: Double.self) { appearance.largeSize = large }
        if let magnification = value("magnification", as: Bool.self) { appearance.magnification = magnification }
        if let autohide = value("autohide", as: Bool.self) { appearance.autohide = autohide }
        if let recents = value("show-recents", as: Bool.self) { appearance.showRecents = recents }
        if let minimize = value("minimize-to-application", as: Bool.self) { appearance.minimizeIntoIcon = minimize }
        return appearance
    }

    static func readHideState() -> DockHideState {
        CFPreferencesAppSynchronize(domain)
        return DockHideState(
            autohide: value("autohide", as: Bool.self) ?? false,
            autohideDelay: value("autohide-delay", as: Double.self)
        )
    }

    // MARK: - Writing

    /// `hideState`, when given, is written after the profile's own Dock settings:
    /// `.parked` keeps the macOS Dock out of the way of a combined custom dock, and
    /// the state read before that puts it back once that is over.
    static func apply(profile: DockProfile, hideState: DockHideState? = nil) throws {
        write(tiles: profile.apps, to: .apps)
        if profile.managesOthers {
            write(tiles: profile.others, to: .others)
        }
        if profile.appearance.enabled {
            write(appearance: profile.appearance)
        }
        if let hideState {
            write(hideState: hideState)
        }
        guard CFPreferencesAppSynchronize(domain) else {
            throw DockServiceError.preferencesWriteFailed
        }
    }

    private static func write(tiles: [DockTile], to section: DockSection) {
        // The Dock draws Finder itself; pinning it as well gives the Dock two of them.
        // A profile can still carry Finder for its custom dock, which has no Finder
        // of its own.
        let array = tiles.filter { !$0.isFinder }.map { $0.dockDictionary() } as CFArray
        CFPreferencesSetAppValue(section.preferenceKey as CFString, array, domain)
    }

    static func write(hideState: DockHideState) {
        CFPreferencesSetAppValue("autohide" as CFString, hideState.autohide as CFBoolean, domain)
        if let delay = hideState.autohideDelay {
            CFPreferencesSetAppValue("autohide-delay" as CFString, delay as CFNumber, domain)
        } else {
            CFPreferencesSetAppValue("autohide-delay" as CFString, nil, domain)
        }
    }

    /// Writes a hide state on its own and restarts the Dock — for putting it back
    /// when the app quits, or parking it again at launch.
    static func applyHideStateNow(_ hideState: DockHideState) {
        write(hideState: hideState)
        CFPreferencesAppSynchronize(domain)
        restartDock()
    }

    private static func write(appearance: DockAppearance) {
        CFPreferencesSetAppValue("orientation" as CFString, appearance.orientation.rawValue as CFString, domain)
        CFPreferencesSetAppValue("tilesize" as CFString, appearance.tileSize as CFNumber, domain)
        CFPreferencesSetAppValue("largesize" as CFString, appearance.largeSize as CFNumber, domain)
        CFPreferencesSetAppValue("magnification" as CFString, appearance.magnification as CFBoolean, domain)
        CFPreferencesSetAppValue("autohide" as CFString, appearance.autohide as CFBoolean, domain)
        CFPreferencesSetAppValue("show-recents" as CFString, appearance.showRecents as CFBoolean, domain)
        CFPreferencesSetAppValue("minimize-to-application" as CFString, appearance.minimizeIntoIcon as CFBoolean, domain)
    }

    // MARK: - Restarting

    static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }

    static var isDockRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").isEmpty
    }

    /// Waits for the Dock to come back after a restart so anything that depends on
    /// it (Mission Control, for instance) is ready before we drive it.
    static func waitForDockRelaunch(timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        // Give the old process a moment to actually die first.
        try? await Task.sleep(nanoseconds: 300_000_000)
        while Date() < deadline {
            if isDockRunning {
                try? await Task.sleep(nanoseconds: 400_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Path of the preferences file, used by the change watcher.
    static var preferencesFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }
}
