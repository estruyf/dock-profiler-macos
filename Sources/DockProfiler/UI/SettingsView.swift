import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch Dock Profiler at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Use the active profile's icon in the menu bar", isOn: $settings.showProfileIconInMenuBar)
                Text("The menu bar shows the glyph of whichever profile is active instead of the Dock Profiler icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Ask before deleting a profile", isOn: $settings.confirmBeforeDelete)
                LabeledContent("Welcome screen") {
                    Button("Show again") { WelcomeWindowController.shared.show() }
                }
            }

            Section("Quick switcher") {
                Toggle("Global shortcut", isOn: $settings.switcherShortcutEnabled)
                LabeledContent("Shortcut") {
                    ShortcutRecorderView(combo: $settings.switcherShortcut)
                        .disabled(!settings.switcherShortcutEnabled)
                }
                if settings.shortcutRegistrationFailed {
                    Label(
                        "macOS refused this shortcut — another app is probably using it. Try a different one.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                Text("Press it anywhere to open a Spotlight-style window, type a few letters and press Return to switch profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open the switcher now") {
                    SwitcherWindowController.shared.show()
                }
            }

            Section("Active profile") {
                Toggle("Keep the active profile in sync with the Dock", isOn: $settings.autoSaveActiveProfile)
                Text("When you drag an app into or out of the Dock, the profile you last activated is updated to match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Profiles are stored locally") {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            store.storeDirectory.appendingPathComponent("profiles.json")
                        ])
                    }
                }
                Text("No account, no sync, no analytics. Everything stays in ~/Library/Application Support/Dock Profiler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toolbar { toolbarContent }
    }

    /// The profile pane names itself in the titlebar; without a matching item
    /// here the toolbar changes height as you move between the two and the
    /// detail pane jumps.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            PaneTitle(symbol: "gearshape", tint: .secondary) {
                Text("Settings").font(.system(size: 15, weight: .semibold))
            }
        }
    }
}
