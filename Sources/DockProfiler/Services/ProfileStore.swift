import AppKit
import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profiles: [DockProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published var isApplying = false
    @Published var lastError: String?
    @Published var lastActivatedAt: Date?

    private let settings = AppSettings.shared
    private let watcher = DockWatcher()
    /// While a profile is being applied the Dock changes because of us, not the user.
    private var ignoreDockChangesUntil = Date.distantPast
    private var saveTask: Task<Void, Never>?

    private var storeURL: URL {
        // DOCKPROFILER_STORE_DIR lets the screenshot tool run against demo profiles
        // instead of the ones you actually use.
        let support: URL
        if let override = ProcessInfo.processInfo.environment["DOCKPROFILER_STORE_DIR"], !override.isEmpty {
            support = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dock Profiler", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("profiles.json")
    }

    var storeDirectory: URL { storeURL.deletingLastPathComponent() }

    private init() {
        load()
        watcher.start { [weak self] in
            self?.dockChangedExternally()
        }
    }

    var activeProfile: DockProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    func profile(_ id: UUID?) -> DockProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    /// Two-way access to a profile so editors can bind straight to the store.
    func binding(for id: UUID) -> Binding<DockProfile> {
        Binding(
            get: { self.profiles.first { $0.id == id } ?? DockProfile.empty() },
            set: { self.update($0) }
        )
    }

    // MARK: - Persistence

    private struct StoreFile: Codable {
        var profiles: [DockProfile]
        var activeProfileID: UUID?
    }

    /// Set when the store on disk could not be read. Nothing is written back
    /// while this is true, so a file a newer build wrote is never replaced by an
    /// empty one.
    private(set) var loadFailed = false

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            let file = try JSONDecoder().decode(StoreFile.self, from: data)
            profiles = file.profiles
            activeProfileID = file.activeProfileID
        } catch {
            loadFailed = true
            let copy = storeURL.deletingLastPathComponent()
                .appendingPathComponent("profiles-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: storeURL, to: copy)
            lastError = "Could not read your profiles (\(error.localizedDescription)). They are untouched, and a copy was kept next to them as \(copy.lastPathComponent)."
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        guard !loadFailed else { return }
        let file = StoreFile(profiles: profiles, activeProfileID: activeProfileID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Editing

    func update(_ profile: DockProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.updatedAt = Date()
        profiles[index] = updated
        scheduleSave()
    }

    @discardableResult
    func createProfile(named name: String, capturingCurrentDock: Bool = true) -> DockProfile {
        var profile = DockProfile.empty(named: name)
        profile.color = ProfileColor.allCases[profiles.count % ProfileColor.allCases.count]
        if capturingCurrentDock {
            let snapshot = DockService.snapshot()
            profile.apps = snapshot.apps
            profile.others = snapshot.others
            var appearance = snapshot.appearance
            appearance.enabled = false
            profile.appearance = appearance
        }
        profiles.append(profile)
        scheduleSave()
        return profile
    }

    @discardableResult
    func duplicate(_ id: UUID) -> DockProfile? {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = profiles[index]
        copy.id = UUID()
        copy.name += " Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        profiles.insert(copy, at: index + 1)
        scheduleSave()
        return copy
    }

    /// Adds profiles read from a file, each under a name no other profile has.
    /// They keep their colours and glyphs; the ids and dates were made fresh on
    /// the way in.
    @discardableResult
    func add(_ imported: [DockProfile]) -> [DockProfile] {
        var added: [DockProfile] = []
        for var profile in imported {
            profile.name = uniqueName(profile.name)
            profiles.append(profile)
            added.append(profile)
        }
        if !added.isEmpty { scheduleSave() }
        return added
    }

    /// `name`, or `name 2`, `name 3`… when a profile already has it.
    func uniqueName(_ name: String) -> String {
        guard profiles.contains(where: { $0.name == name }) else { return name }
        var index = 2
        while profiles.contains(where: { $0.name == "\(name) \(index)" }) { index += 1 }
        return "\(name) \(index)"
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        scheduleSave()
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: offsets, toOffset: destination)
        scheduleSave()
    }

    /// Replaces a profile's items with whatever is pinned to the Dock right now.
    func captureCurrentDock(into id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = DockService.snapshot()
        profiles[index].apps = snapshot.apps
        profiles[index].others = snapshot.others
        if profiles[index].appearance.enabled {
            var appearance = snapshot.appearance
            appearance.enabled = true
            profiles[index].appearance = appearance
        }
        profiles[index].updatedAt = Date()
        scheduleSave()
    }

    // MARK: - Activating

    func activate(_ id: UUID) {
        guard let profile = profile(id) else { return }
        Task { await activate(profile) }
    }

    func activate(_ profile: DockProfile) async {
        guard !isApplying else { return }
        isApplying = true
        lastError = nil
        ignoreDockChangesUntil = Date().addingTimeInterval(6)
        defer { isApplying = false }

        // A combined custom dock stands in for the macOS Dock, so the Dock is parked
        // — auto-hidden, and never coming back on hover — for as long as such a
        // profile is active. Its own settings come back with the next profile that
        // neither stands in for it nor manages Dock settings itself.
        var hideState: DockHideState?
        if profile.customDock.isCombined {
            if settings.dockStateBeforeCustomDock == nil {
                settings.dockStateBeforeCustomDock = DockService.readHideState()
            }
            hideState = .parked
        } else if let previous = settings.dockStateBeforeCustomDock {
            hideState = profile.appearance.enabled ? DockHideState(autohide: profile.appearance.autohide, autohideDelay: previous.autohideDelay) : previous
            settings.dockStateBeforeCustomDock = nil
        }

        do {
            try DockService.apply(profile: profile, hideState: hideState)
            activeProfileID = profile.id
            saveNow()
            DockService.restartDock()
            await DockService.waitForDockRelaunch()
        } catch {
            lastError = error.localizedDescription
            return
        }

        if profile.desktop.setsWallpaper, let path = profile.desktop.wallpaperPath {
            do {
                try WallpaperService.apply(path: path, allScreens: profile.desktop.wallpaperAllScreens)
            } catch {
                lastError = error.localizedDescription
            }
        }

        ignoreDockChangesUntil = Date().addingTimeInterval(3)
        lastActivatedAt = Date()
    }

    // MARK: - Parking the Dock across launches

    /// At launch: if the active profile stands in for the Dock, park it again (the
    /// Dock was put back when the app last quit).
    func parkDockIfNeeded() {
        guard let profile = activeProfile, profile.customDock.isCombined else { return }
        let current = DockService.readHideState()
        guard current != .parked else { return }
        if settings.dockStateBeforeCustomDock == nil {
            settings.dockStateBeforeCustomDock = current
        }
        ignoreDockChangesUntil = Date().addingTimeInterval(6)
        DockService.applyHideStateNow(.parked)
    }

    /// At quit: the custom dock goes away with the app, so the macOS Dock comes back.
    func restoreDockIfNeeded() {
        guard let previous = settings.dockStateBeforeCustomDock else { return }
        settings.dockStateBeforeCustomDock = nil
        DockService.applyHideStateNow(previous)
    }

    // MARK: - Auto-save

    private func dockChangedExternally() {
        guard settings.autoSaveActiveProfile else { return }
        guard Date() > ignoreDockChangesUntil, !isApplying else { return }
        guard let id = activeProfileID, let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let snapshot = DockService.snapshot()
        var changed = false

        // Finder is never in the Dock's own list, so it is left out of the comparison
        // and kept where the profile had it.
        let pinned = profiles[index].apps.filter { !$0.isFinder }
        if snapshot.apps.map(\.raw) != pinned.map(\.raw) {
            var apps = snapshot.apps
            if let finderIndex = profiles[index].apps.firstIndex(where: \.isFinder) {
                apps.insert(profiles[index].apps[finderIndex], at: min(finderIndex, apps.count))
            }
            profiles[index].apps = apps
            changed = true
        }
        if profiles[index].managesOthers,
           snapshot.others.map(\.raw) != profiles[index].others.map(\.raw) {
            profiles[index].others = snapshot.others
            changed = true
        }
        if profiles[index].appearance.enabled {
            var appearance = snapshot.appearance
            appearance.enabled = true
            if appearance != profiles[index].appearance {
                profiles[index].appearance = appearance
                changed = true
            }
        }

        guard changed else { return }
        profiles[index].updatedAt = Date()
        scheduleSave()
    }
}
