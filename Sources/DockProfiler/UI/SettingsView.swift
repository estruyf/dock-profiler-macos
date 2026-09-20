import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var badges = DockBadgeMonitor.shared
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
                } else if settings.switcherShortcut?.togglesDockHiding == true {
                    Label(
                        "⌥⌘D is macOS's shortcut for hiding the Dock, and it keeps doing that alongside opening the switcher. Try a different one.",
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

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if badges.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Accessibility Settings…") {
                            badges.requestAccess()
                            DockBadgeMonitor.openAccessibilitySettings()
                        }
                    }
                }
                Text("Optional. Lets a custom dock show the Dock's notification badges on its app tiles, read from the macOS Dock, and list an app's open windows in its tile's menu. Nothing else is read. Every other permission is asked for in place, by the widget that needs it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            Section("About") {
                AboutRow()
            }
        }
        .formStyle(.grouped)
        .onAppear { badges.refreshTrust() }
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

/// The icon, the version and where to go from here. There is no main menu for
/// a standard About panel to hang off, so this row is it.
private struct AboutRow: View {
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: AppInfo.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Text(AppInfo.versionDescription)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button {
                        copyVersion()
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy the version and macOS build, for a bug report")
                }
                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 12) {
                    Link("GitHub", destination: AppInfo.repository)
                    Link("What's new", destination: AppInfo.changelog)
                    Link("Report an issue", destination: AppInfo.issues)
                }
                .font(.caption)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func copyVersion() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppInfo.diagnosticSummary, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}
