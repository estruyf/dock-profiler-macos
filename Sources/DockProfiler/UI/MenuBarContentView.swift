import AppKit
import SwiftUI

/// SwiftUI gives no way to close a `MenuBarExtra` panel, so we ask AppKit.
enum MenuBarPanel {
    static func dismiss() {
        for window in NSApp.windows where window.className.contains("MenuBarExtra") {
            window.close()
        }
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.profiles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.profiles) { profile in
                            ProfileMenuRow(
                                profile: profile,
                                isActive: profile.id == store.activeProfileID,
                                action: { activate(profile) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                // A ScrollView has no height of its own: inside the menu bar panel
                // `maxHeight` alone collapses it to nothing, so measure the rows.
                .frame(height: listHeight)
            }

            if let error = store.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .frame(width: 300)
        .background(MenuBackground())
    }

    /// Tall enough for every profile, up to a point, then it scrolls.
    private var listHeight: CGFloat {
        // Row: 26pt glyph + 6pt padding either side, 2pt between rows, 6pt top and bottom.
        let rows = CGFloat(store.profiles.count)
        return min(rows * 40 + 14, 320)
    }

    private var header: some View {
        HStack {
            Label("Dock Profiler", systemImage: "dock.rectangle")
                .font(.headline)
            Spacer()
            if store.isApplying {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No profiles yet")
                .font(.subheadline.weight(.medium))
            Text("Save your current Dock to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            MenuActionRow(
                title: "Quick Switch…",
                systemImage: "magnifyingglass",
                trailing: settings.switcherShortcutEnabled ? settings.switcherShortcut?.displayString : nil
            ) {
                MenuBarPanel.dismiss()
                SwitcherWindowController.shared.show()
            }
            MenuActionRow(title: "Save current Dock as profile…", systemImage: "plus.circle") {
                let profile = store.createProfile(named: suggestedName())
                MenuBarPanel.dismiss()
                WindowRouter.shared.pendingRename = profile.id
                openManager(selecting: profile.id)
            }
            MenuActionRow(title: "Manage profiles…", systemImage: "slider.horizontal.3") {
                MenuBarPanel.dismiss()
                openManager(selecting: store.activeProfileID)
            }
            MenuActionRow(title: "Settings…", systemImage: "gearshape") {
                MenuBarPanel.dismiss()
                ManagerWindowController.shared.showSettings()
            }
            MenuActionRow(title: "Quit Dock Profiler", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func activate(_ profile: DockProfile) {
        MenuBarPanel.dismiss()
        store.activate(profile.id)
    }

    private func openManager(selecting id: UUID?) {
        ManagerWindowController.shared.show(selecting: id)
    }

    private func suggestedName() -> String {
        let base = "Profile"
        var index = store.profiles.count + 1
        var name = "\(base) \(index)"
        while store.profiles.contains(where: { $0.name == name }) {
            index += 1
            name = "\(base) \(index)"
        }
        return name
    }
}

/// Blur, plus a tint heavy enough that the desktop behind never washes the menu out.
private struct MenuBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Color(nsColor: .windowBackgroundColor).opacity(0.80)
        }
    }
}

private struct ProfileMenuRow: View {
    let profile: DockProfile
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(profile.color.color.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: profile.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(profile.color.color)
                }
                Text(profile.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                Spacer(minLength: 4)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(profile.color.color)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct MenuRowLabel: View {
    let title: String
    let systemImage: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 13))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
            .onHover { isHovering = $0 }
    }
}

private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    var trailing: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, systemImage: systemImage, trailing: trailing)
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}
