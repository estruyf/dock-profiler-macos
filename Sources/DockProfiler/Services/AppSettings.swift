import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let autoSave = "autoSaveActiveProfile"
        static let spaceMethod = "spaceSwitchMethod"
        static let showNameInMenuBar = "showProfileNameInMenuBar"
        static let confirmBeforeDelete = "confirmBeforeDelete"
        static let switcherShortcut = "switcherShortcut"
        static let switcherShortcutEnabled = "switcherShortcutEnabled"
        static let hasSeenWelcome = "hasSeenWelcome"
    }

    private let defaults = UserDefaults.standard

    /// Keeps the active profile in sync with the Dock while you rearrange it.
    @Published var autoSaveActiveProfile: Bool {
        didSet { defaults.set(autoSaveActiveProfile, forKey: Key.autoSave) }
    }

    @Published var spaceSwitchMethod: SpaceSwitchMethod {
        didSet { defaults.set(spaceSwitchMethod.rawValue, forKey: Key.spaceMethod) }
    }

    @Published var showProfileNameInMenuBar: Bool {
        didSet { defaults.set(showProfileNameInMenuBar, forKey: Key.showNameInMenuBar) }
    }

    @Published var confirmBeforeDelete: Bool {
        didSet { defaults.set(confirmBeforeDelete, forKey: Key.confirmBeforeDelete) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != isRegisteredAsLoginItem else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                loginItemError = error.localizedDescription
            }
        }
    }

    @Published var loginItemError: String?

    /// Global shortcut that opens the quick switcher.
    @Published var switcherShortcut: KeyCombo? {
        didSet {
            if let data = try? JSONEncoder().encode(switcherShortcut) {
                defaults.set(data, forKey: Key.switcherShortcut)
            } else {
                defaults.removeObject(forKey: Key.switcherShortcut)
            }
            applyShortcut()
        }
    }

    @Published var switcherShortcutEnabled: Bool {
        didSet {
            defaults.set(switcherShortcutEnabled, forKey: Key.switcherShortcutEnabled)
            applyShortcut()
        }
    }

    /// True when macOS refused the combination — usually another app owns it.
    @Published var shortcutRegistrationFailed = false

    @Published var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    private init() {
        defaults.register(defaults: [
            Key.autoSave: true,
            Key.showNameInMenuBar: false,
            Key.confirmBeforeDelete: true,
            Key.switcherShortcutEnabled: true,
        ])
        autoSaveActiveProfile = defaults.bool(forKey: Key.autoSave)
        showProfileNameInMenuBar = defaults.bool(forKey: Key.showNameInMenuBar)
        confirmBeforeDelete = defaults.bool(forKey: Key.confirmBeforeDelete)
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
        spaceSwitchMethod = SpaceSwitchMethod(
            rawValue: defaults.string(forKey: Key.spaceMethod) ?? ""
        ) ?? .arrows
        launchAtLogin = SMAppService.mainApp.status == .enabled
        switcherShortcutEnabled = defaults.bool(forKey: Key.switcherShortcutEnabled)
        if let data = defaults.data(forKey: Key.switcherShortcut) {
            switcherShortcut = try? JSONDecoder().decode(KeyCombo.self, from: data)
        } else {
            switcherShortcut = .defaultSwitcher
        }
    }

    /// Registers (or clears) the global shortcut. Called at launch and on change.
    func applyShortcut() {
        let succeeded = HotKeyManager.shared.register(switcherShortcutEnabled ? switcherShortcut : nil)
        shortcutRegistrationFailed = !succeeded
    }

    private var isRegisteredAsLoginItem: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func refreshLoginItemStatus() {
        let enabled = isRegisteredAsLoginItem
        if enabled != launchAtLogin { launchAtLogin = enabled }
    }
}
