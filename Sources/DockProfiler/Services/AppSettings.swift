import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let autoSave = "autoSaveActiveProfile"
        // The name is historical: the menu bar only ever showed the glyph.
        static let showIconInMenuBar = "showProfileNameInMenuBar"
        static let confirmBeforeDelete = "confirmBeforeDelete"
        static let switcherShortcut = "switcherShortcut"
        static let switcherShortcutEnabled = "switcherShortcutEnabled"
        static let hasSeenWelcome = "hasSeenWelcome"
        static let dockStateBeforeCustomDock = "dockStateBeforeCustomDock"
    }

    private let defaults = UserDefaults.standard

    /// Keeps the active profile in sync with the Dock while you rearrange it.
    @Published var autoSaveActiveProfile: Bool {
        didSet { defaults.set(autoSaveActiveProfile, forKey: Key.autoSave) }
    }

    /// Swaps the menu bar glyph for the active profile's own.
    @Published var showProfileIconInMenuBar: Bool {
        didSet { defaults.set(showProfileIconInMenuBar, forKey: Key.showIconInMenuBar) }
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

    /// A combined custom dock parks the macOS Dock. These are the Dock's own settings
    /// from before we did that, so they can be put back afterwards.
    var dockStateBeforeCustomDock: DockHideState? {
        get {
            guard let data = defaults.data(forKey: Key.dockStateBeforeCustomDock) else { return nil }
            return try? JSONDecoder().decode(DockHideState.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.dockStateBeforeCustomDock)
            } else {
                defaults.removeObject(forKey: Key.dockStateBeforeCustomDock)
            }
        }
    }

    private init() {
        defaults.register(defaults: [
            Key.autoSave: true,
            Key.showIconInMenuBar: false,
            Key.confirmBeforeDelete: true,
            Key.switcherShortcutEnabled: true,
        ])
        autoSaveActiveProfile = defaults.bool(forKey: Key.autoSave)
        showProfileIconInMenuBar = defaults.bool(forKey: Key.showIconInMenuBar)
        confirmBeforeDelete = defaults.bool(forKey: Key.confirmBeforeDelete)
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
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
