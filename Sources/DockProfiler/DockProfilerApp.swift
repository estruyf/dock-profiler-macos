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
            if settings.showProfileNameInMenuBar, let profile = store.activeProfile {
                Label(profile.name, systemImage: profile.symbol)
            } else {
                Image(systemName: "dock.rectangle")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            AppSettings.shared.refreshLoginItemStatus()
            HotKeyManager.shared.onTrigger = {
                SwitcherWindowController.shared.toggle()
            }
            AppSettings.shared.applyShortcut()
            if ProfileStore.shared.profiles.isEmpty, !AppSettings.shared.hasSeenWelcome {
                WelcomeWindowController.shared.show()
            }
        }
    }

    /// `dockprofiler://switch`, `dockprofiler://profiles`, `dockprofiler://activate?name=Development`
    /// so the switcher can also be driven from Shortcuts, Raycast or a script.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { handle(url) }
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { ManagerWindowController.shared.show() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
