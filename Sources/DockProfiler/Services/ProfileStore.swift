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

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        guard let file = try? JSONDecoder().decode(StoreFile.self, from: data) else { return }
        profiles = file.profiles
        activeProfileID = file.activeProfileID
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

        do {
            try DockService.apply(profile: profile)
            activeProfileID = profile.id
            saveNow()
            DockService.restartDock()
            await DockService.waitForDockRelaunch()
        } catch {
            lastError = error.localizedDescription
            return
        }

        if profile.desktop.switchesSpace {
            do {
                try await SpaceService.switchToDesktop(
                    profile.desktop.spaceIndex,
                    method: settings.spaceSwitchMethod
                )
            } catch {
                lastError = error.localizedDescription
            }
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

    // MARK: - Auto-save

    private func dockChangedExternally() {
        guard settings.autoSaveActiveProfile else { return }
        guard Date() > ignoreDockChangesUntil, !isApplying else { return }
        guard let id = activeProfileID, let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        let snapshot = DockService.snapshot()
        var changed = false

        if snapshot.apps.map(\.raw) != profiles[index].apps.map(\.raw) {
            profiles[index].apps = snapshot.apps
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
