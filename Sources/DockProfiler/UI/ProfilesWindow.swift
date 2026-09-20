import AppKit
import SwiftUI

struct ProfilesWindow: View {
    /// The sidebar lists the profiles and, under them, Settings — which opens in
    /// the same detail pane rather than a window of its own.
    private enum SidebarItem: Hashable {
        case profile(UUID)
        case settings
    }

    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var router = WindowRouter.shared
    @State private var selection: SidebarItem?
    @State private var profilePendingDeletion: DockProfile?

    private var selectedProfileID: UUID? {
        if case .profile(let id) = selection, store.profile(id) != nil { return id }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            if selection == .settings {
                SettingsView()
            } else if let id = selectedProfileID {
                ProfileEditorView(profile: store.binding(for: id))
                    .id(id)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .modifier(NoWindowTitle())
        .background {
            // An accessory app has no main menu for ⌘, to land in, so the window
            // carries the shortcut itself, on a button that is never seen.
            Button("Settings") { selection = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onAppear { syncSelection() }
        .onChange(of: router.pendingSelection) { _, _ in syncSelection() }
        .onChange(of: router.settingsRequest) { _, _ in selection = .settings }
        .onChange(of: store.profiles.count) { _, _ in
            guard selection != .settings else { return }
            if selectedProfileID == nil {
                selection = store.profiles.last.map { .profile($0.id) }
            }
        }
        .alert(
            "Delete “\(profilePendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { if !$0 { profilePendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let profile = profilePendingDeletion { store.delete(profile.id) }
                profilePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { profilePendingDeletion = nil }
        } message: {
            Text("This removes the profile from Dock Profiler. Your Dock is left as it is.")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Profiles") {
                ForEach(store.profiles) { profile in
                    SidebarRow(profile: profile, isActive: profile.id == store.activeProfileID)
                        .tag(SidebarItem.profile(profile.id))
                        .contextMenu {
                            Button("Activate") { store.activate(profile.id) }
                            Button("Capture current Dock") { store.captureCurrentDock(into: profile.id) }
                            Button("Duplicate") {
                                if let copy = store.duplicate(profile.id) { selection = .profile(copy.id) }
                            }
                            Divider()
                            Button("Export…") { ProfileSharing.export([profile]) }
                            Divider()
                            Button("Delete", role: .destructive) { requestDelete(profile) }
                        }
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        // A .dockprofile dropped on the list comes in as a profile.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(ProfileSharing.isProfileFile)
            guard !files.isEmpty else { return false }
            ProfileSharing.importProfiles(from: files)
            return true
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                settingsRow
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                Divider()
                profileActions
            }
            .background(.bar)
        }
    }

    /// Settings sits under the profiles, pinned to the bottom of the sidebar, with
    /// the version beneath its name — the place people look for it in Mail and Notes.
    private var settingsRow: some View {
        let selected = selection == .settings
        return Button {
            selection = .settings
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(selected ? .white : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                    Text(AppInfo.version.map { "Version \($0)" } ?? "Development build")
                        .font(.caption)
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// New, import and delete, along the bottom edge.
    private var profileActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Import…") { ProfileSharing.importFromPanel() }
            } label: {
                Label("New from current Dock", systemImage: "plus")
            } primaryAction: {
                let profile = store.createProfile(named: newProfileName())
                selection = .profile(profile.id)
                router.pendingRename = profile.id
            }
            .controlSize(.small)
            .fixedSize()
            Spacer()
            Button {
                if let profile = store.profile(selectedProfileID) { requestDelete(profile) }
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .disabled(selectedProfileID == nil)
            .help("Delete the selected profile")
        }
        .padding(10)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Select a profile")
                .font(.title3.weight(.medium))
            Text("Or create one from the Dock you are using right now.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("New from current Dock") {
                    let profile = store.createProfile(named: newProfileName())
                    selection = .profile(profile.id)
                    router.pendingRename = profile.id
                }
                Button("Import…") { ProfileSharing.importFromPanel() }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestDelete(_ profile: DockProfile) {
        if AppSettings.shared.confirmBeforeDelete {
            profilePendingDeletion = profile
        } else {
            store.delete(profile.id)
        }
    }

    private func syncSelection() {
        if let pending = router.pendingSelection, store.profile(pending) != nil {
            selection = .profile(pending)
            router.pendingSelection = nil
        } else if selection == nil {
            selection = (store.activeProfileID ?? store.profiles.first?.id).map { .profile($0) }
        }
    }

    private func newProfileName() -> String {
        var index = store.profiles.count + 1
        var name = "Profile \(index)"
        while store.profiles.contains(where: { $0.name == name }) {
            index += 1
            name = "Profile \(index)"
        }
        return name
    }
}

/// SwiftUI puts the window title back in the titlebar whenever the detail pane's
/// toolbar changes — on top of the toolbar that already names the profile, with a
/// rule drawn across it. macOS 15 has a modifier for dropping the title item;
/// before that, `ManagerWindowController` re-hides it on the next window update.
private struct NoWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

private struct SidebarRow: View {
    let profile: DockProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(profile.color.color.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: profile.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(profile.color.color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                Text(profile.itemSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .help("Active now")
            }
        }
        .padding(.vertical, 2)
    }
}
