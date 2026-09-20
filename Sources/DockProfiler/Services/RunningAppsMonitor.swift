import AppKit
import Combine

/// Which apps are running: the dot under the custom dock's app tiles, and the
/// unpinned ones it can show after them, as the Dock does.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    static let shared = RunningAppsMonitor()

    @Published private(set) var bundleIdentifiers: Set<String> = []
    /// Tiles for every running app, oldest launch first, so the row stays steady.
    @Published private(set) var tiles: [DockTile] = []
    private var tokens: [NSObjectProtocol] = []
    private var listObservation: NSKeyValueObservation?

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        // The list itself is observable too; watching it as well covers an app that
        // goes without the notification — one that crashed, or was killed outright.
        listObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        // The Dock only marks apps that could have a Dock tile of their own.
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !$0.isTerminated }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        bundleIdentifiers = Set(apps.compactMap(\.bundleIdentifier))

        // Reuse the tiles we already have so their ids — and so their views — stay put.
        var existing = Dictionary(tiles.compactMap { tile in tile.bundleIdentifier.map { ($0, tile) } },
                                  uniquingKeysWith: { first, _ in first })
        tiles = apps.compactMap { app in
            guard let identifier = app.bundleIdentifier else { return nil }
            if let tile = existing.removeValue(forKey: identifier) { return tile }
            return app.bundleURL.flatMap { DockTile.app(at: $0) }
        }
    }

    func isRunning(_ tile: DockTile) -> Bool {
        guard let identifier = tile.bundleIdentifier else { return false }
        return bundleIdentifiers.contains(identifier)
    }

    /// Running apps that are not among `pinned`.
    func unpinnedTiles(excluding pinned: [DockTile]) -> [DockTile] {
        let pinnedIdentifiers = Set(pinned.compactMap(\.bundleIdentifier))
        return tiles.filter { tile in
            guard let identifier = tile.bundleIdentifier else { return false }
            return !pinnedIdentifiers.contains(identifier)
        }
    }
}
