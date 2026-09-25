import AppKit
import Combine

/// Which of each browser's profiles have a window up, kept current — so a
/// launcher tile for one profile can show its own running dot while another
/// profile's stays dark, the way Windows gives each profile its own taskbar
/// button. macOS runs a browser as one process whatever its profiles do, so
/// the running apps list cannot tell them apart; the browsers' own files can.
///
/// Read again when a browser starts or quits, and when one of the folders the
/// browsers write to changes: Chromium replaces `Local State` a moment after a
/// window opens or closes — it saves preferences on a delay of some seconds, so
/// the dot follows a little behind — and Firefox makes or removes the lock in
/// the profile's folder at once.
@MainActor
final class BrowserProfileMonitor: ObservableObject {
    static let shared = BrowserProfileMonitor()

    /// The open profiles' ids, by the browser's bundle identifier.
    @Published private(set) var openProfiles: [String: Set<String>] = [:]

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var debounce: Task<Void, Never>?
    private var runningObservation: AnyCancellable?
    private var accessObservation: AnyCancellable?

    private init() {
        refresh()
        runningObservation = RunningAppsMonitor.shared.$bundleIdentifiers
            .dropFirst()
            .sink { [weak self] _ in
                // A browser that just started has still to open its windows and
                // write that down; a second look a moment later catches it.
                self?.refresh()
                self?.scheduleRefresh()
            }
        // Access granted in System Settings: the files can be read now.
        accessObservation = BrowserDataAccess.shared.$status
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRefresh() }
    }

    /// Whether the profile has a window up — false for a browser that is not
    /// running, or not one whose profiles are known.
    func isOpen(_ profileID: String, of bundleIdentifier: String) -> Bool {
        openProfiles[bundleIdentifier]?.contains(profileID) ?? false
    }

    /// Whether a launcher counts as running: its app is up and, for a browser
    /// opened as one of its profiles, that profile has a window. A launcher with
    /// no profile goes by the app alone.
    func isRunning(_ tile: WidgetTile, among running: Set<String>) -> Bool {
        guard let identifier = tile.appURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }),
              running.contains(identifier) else { return false }
        guard let profile = tile.browserProfile else { return true }
        return isOpen(profile.id, of: identifier)
    }

    private func refresh() {
        var open: [String: Set<String>] = [:]
        var directories: [URL] = []
        for browser in BrowserProfiles.knownBrowsers {
            let profiles = BrowserProfiles.openProfiles(of: browser)
            if !profiles.isEmpty { open[browser] = profiles }
            directories += BrowserProfiles.watchedDirectories(of: browser)
        }
        if open != openProfiles { openProfiles = open }
        watch(directories)
    }

    /// Browsers write a few files in a row; one read after the last is enough.
    private func scheduleRefresh() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self.refresh()
        }
    }

    /// Keeps a watcher on each folder, dropping those that are gone. A file
    /// replaced in a folder — as `Local State` is — or a lock added or removed
    /// shows up as a write to the folder, so the folder is what is watched.
    private func watch(_ directories: [URL]) {
        let paths = Set(directories.map(\.path))
        for path in watchers.keys where !paths.contains(path) {
            watchers.removeValue(forKey: path)?.cancel()
        }
        for path in paths where watchers[path] == nil {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watchers[path] = source
        }
    }
}
