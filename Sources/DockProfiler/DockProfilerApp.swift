import AppKit
import SwiftUI

@main
struct DockProfilerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ProfileStore.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
        } label: {
            // A `MenuBarExtra` label draws the glyph and drops the title, so the
            // name goes to the accessibility label rather than on screen.
            if settings.showProfileIconInMenuBar, let profile = store.activeProfile {
                Image(systemName: profile.symbol)
                    .accessibilityLabel("Dock Profiler — \(profile.name)")
            } else {
                Image(systemName: "dock.rectangle")
                    .accessibilityLabel("Dock Profiler")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // `kill` and `killall` skip applicationWillTerminate; the macOS Dock must
        // still come back if we parked it.
        signal(SIGTERM, SIG_IGN)
        terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal?.setEventHandler {
            MainActor.assumeIsolated { ProfileStore.shared.restoreDockIfNeeded() }
            exit(0)
        }
        terminationSignal?.resume()
        MainActor.assumeIsolated {
            AppSettings.shared.refreshLoginItemStatus()
            HotKeyManager.shared.onTrigger = {
                SwitcherWindowController.shared.toggle()
            }
            AppSettings.shared.applyShortcut()
            CustomDockWindowController.shared.start()
            ProfileStore.shared.parkDockIfNeeded()
            if ProfileStore.shared.profiles.isEmpty, !AppSettings.shared.hasSeenWelcome {
                WelcomeWindowController.shared.show()
            }
        }
    }

    /// `dockprofiler://switch`, `dockprofiler://profiles`, `dockprofiler://activate?name=Development`
    /// so the switcher can also be driven from Shortcuts, Raycast or a script —
    /// and `.dockprofile` files opened from Finder, which are imported.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            let files = urls.filter(ProfileSharing.isProfileFile)
            if !files.isEmpty { ProfileSharing.importProfiles(from: files) }
            for url in urls where !url.isFileURL { handle(url) }
        }
    }

    @MainActor
    private func handle(_ url: URL) {
        let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch command {
        case "switch", "switcher":
            SwitcherWindowController.shared.toggle()
        case "profiles", "manage":
            ManagerWindowController.shared.show()
        case "welcome":
            WelcomeWindowController.shared.show()
        case "activate":
            let store = ProfileStore.shared
            let profile: DockProfile?
            if let id = query.first(where: { $0.name == "id" })?.value.flatMap(UUID.init) {
                profile = store.profile(id)
            } else if let name = query.first(where: { $0.name == "name" })?.value?.lowercased() {
                profile = store.profiles.first { $0.name.lowercased() == name }
            } else {
                profile = nil
            }
            if let profile { store.activate(profile.id) }
        default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { ProfileStore.shared.restoreDockIfNeeded() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { ManagerWindowController.shared.show() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
