import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var store: ProfileStore
    @State private var hasAccessibility = SpaceService.hasAccessibilityAccess

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch Dock Profiler at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show the active profile name in the menu bar", isOn: $settings.showProfileNameInMenuBar)
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

            Section("Desktops") {
                Picker("Switch desktops using", selection: $settings.spaceSwitchMethod) {
                    ForEach(SpaceSwitchMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                Text(settings.spaceSwitchMethod.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Accessibility access") {
                    HStack(spacing: 8) {
                        Label(
                            hasAccessibility ? "Granted" : "Not granted",
                            systemImage: hasAccessibility ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(hasAccessibility ? .green : .orange)
                        Button("Open Settings…") {
                            SpaceService.requestAccessibilityAccess()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
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
        .frame(width: 520, height: 520)
        .onAppear { hasAccessibility = SpaceService.hasAccessibilityAccess }
    }
}
