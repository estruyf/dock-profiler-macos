import AppKit
import SwiftUI

struct ProfilesWindow: View {
    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var router = WindowRouter.shared
    @State private var selection: UUID?
    @State private var profilePendingDeletion: DockProfile?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            if let selection, store.profile(selection) != nil {
                ProfileEditorView(profile: store.binding(for: selection))
                    .id(selection)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { syncSelection() }
        .onChange(of: router.pendingSelection) { _, _ in syncSelection() }
        .onChange(of: store.profiles.count) { _, _ in
            if selection == nil || store.profile(selection) == nil {
                selection = store.profiles.last?.id
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
                        .tag(profile.id)
                        .contextMenu {
                            Button("Activate") { store.activate(profile.id) }
                            Button("Capture current Dock") { store.captureCurrentDock(into: profile.id) }
                            Button("Duplicate") {
                                if let copy = store.duplicate(profile.id) { selection = copy.id }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { requestDelete(profile) }
                        }
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    let profile = store.createProfile(named: newProfileName())
                    selection = profile.id
                    router.pendingRename = profile.id
                } label: {
                    Label("New from current Dock", systemImage: "plus")
                }
                .controlSize(.small)
                Spacer()
                Button {
                    if let profile = store.profile(selection) { requestDelete(profile) }
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .disabled(selection == nil)
                .help("Delete the selected profile")
            }
            .padding(10)
            .background(.bar)
        }
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
            Button("New from current Dock") {
                let profile = store.createProfile(named: newProfileName())
                selection = profile.id
                router.pendingRename = profile.id
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
            selection = pending
            router.pendingSelection = nil
        } else if selection == nil {
            selection = store.activeProfileID ?? store.profiles.first?.id
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
