import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum EditorTab: String, CaseIterable, Identifiable {
    case items, dock, desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .items: return "Items"
        case .dock: return "Dock"
        case .desktop: return "Desktop"
        }
    }
}

struct ProfileEditorView: View {
    @EnvironmentObject private var store: ProfileStore
    @Binding var profile: DockProfile

    @State private var tab: EditorTab = .items
    @State private var section: DockSection = .apps
    @State private var selection: UUID?
    @State private var showingIdentity = false
    @State private var titleHovering = false
    @ObservedObject private var router = WindowRouter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                activationSentence
                dockPreview
                hintRow
                tabBar
                tabContent
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDeleteCommand(perform: removeSelection)
        .onAppear {
            // A profile created a moment ago still has a placeholder name.
            if router.pendingRename == profile.id {
                router.pendingRename = nil
                showingIdentity = true
            }
        }
        .toolbar { toolbarContent }
    }

    // MARK: - What activation will do

    private var appCount: Int { profile.apps.filter { !$0.kind.isSpacer }.count }

    private var activationSentence: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            sentence
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var sentence: Text {
        var text = Text("Activating ") + Text(profile.name).bold()
            + Text(" replaces the ") + Text("\(appCount) pinned app\(appCount == 1 ? "" : "s")").bold()
            + Text(" in your Dock")

        if profile.managesOthers {
            text = text + Text(" and its ") + Text("folders & files").bold()
        }
        if profile.appearance.enabled {
            text = text + Text(", applies your ") + Text("Dock settings").bold()
        }
        if profile.desktop.setsWallpaper, profile.desktop.wallpaperPath != nil {
            text = text + Text(" and sets its ") + Text("wallpaper").bold()
        }
        text = text + Text(". ")

        var untouched = ["open apps"]
        if !profile.appearance.enabled { untouched.insert("Dock size", at: 0) }
        if !profile.managesOthers { untouched.insert("folders", at: untouched.count - 1) }
        let list: String
        switch untouched.count {
        case 1: list = untouched[0]
        case 2: list = "\(untouched[0]) and \(untouched[1])"
        default: list = untouched.dropLast().joined(separator: ", ") + ", and " + (untouched.last ?? "")
        }
        return text + Text("Your \(list) stay as they are.").foregroundColor(.secondary)
    }

    // MARK: - Dock preview

    private var tilesBinding: Binding<[DockTile]> {
        Binding(
            get: { section == .apps ? profile.apps : profile.others },
            set: { if section == .apps { profile.apps = $0 } else { profile.others = $0 } }
        )
    }

    private var tiles: [DockTile] { tilesBinding.wrappedValue }

    private var dockPreview: some View {
        DockPreviewStrip(
            tiles: tilesBinding,
            selection: $selection,
            onAdd: addFromPanel,
            onDropURLs: add
        )
    }

    private var hintRow: some View {
        HStack {
            Text("Drag to reorder · right-click or ⌫ to remove · drop an app from Finder to add")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let tile = tiles.first(where: { $0.id == selection }) {
                Text(tile.label).font(.system(size: 12, weight: .medium))
                    + Text(" selected").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(EditorTab.allCases) { value in
                Button {
                    tab = value
                } label: {
                    HStack(spacing: 6) {
                        Text(value.title)
                            .font(.system(size: 13, weight: tab == value ? .semibold : .regular))
                        switch value {
                        case .items:
                            Text("\(tiles.count)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        case .dock:
                            dot(profile.appearance.enabled ? Color.secondary : .clear)
                        case .desktop:
                            dot(profile.desktop.isActive ? Color.accentColor : .clear)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == value ? Color(nsColor: .textBackgroundColor) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(tab == value ? 0.10 : 0))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch tab {
            case .items: itemsTab
            case .dock: dockTab
            case .desktop: DesktopOptionsView(options: $profile.desktop)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Items

    private var itemsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                sectionButton(.apps, label: "Apps · \(profile.apps.count)")
                sectionButton(
                    .others,
                    label: profile.managesOthers ? "Folders & files · \(profile.others.count)" : "Folders & files · off"
                )
                Spacer()
                Button(action: addFromPanel) {
                    Text(section == .apps ? "Add app…" : "Add folder…")
                }
                if section == .apps {
                    Menu("Add spacer") {
                        Button("Spacer") { append(DockTile.spacer(.spacer)) }
                        Button("Small spacer") { append(DockTile.spacer(.smallSpacer)) }
                    }
                    .fixedSize()
                }
                Button {
                    store.captureCurrentDock(into: profile.id)
                } label: {
                    Label("Capture my Dock", systemImage: "square.and.arrow.down")
                }
            }

            if section == .others && !profile.managesOthers {
                foldersDisabledState
            } else if tiles.isEmpty {
                emptyItemsState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(tiles) { tile in
                        ItemCard(tile: tile, isSelected: selection == tile.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = tile.id }
                            .contextMenu {
                                Button("Remove from profile", role: .destructive) {
                                    tilesBinding.wrappedValue.removeAll { $0.id == tile.id }
                                }
                            }
                    }
                }
            }
        }
    }

    private func sectionButton(_ value: DockSection, label: String) -> some View {
        Button {
            section = value
            selection = nil
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(section == value ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(section == value ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(section == value ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
    }

    private var foldersDisabledState: some View {
        VStack(spacing: 8) {
            Text("This profile leaves folders and files alone")
                .font(.system(size: 13, weight: .medium))
            Text("The right-hand side of your Dock — folders, stacks, the Downloads pile — stays exactly as it is when you activate.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Manage them in this profile") {
                profile.managesOthers = true
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyItemsState: some View {
        VStack(spacing: 6) {
            Text("Nothing here yet")
                .font(.system(size: 13, weight: .medium))
            Text("Add apps above, drop them in from Finder, or capture the Dock you are using now.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Dock settings

    private var dockTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Apply these Dock settings when the profile is activated", isOn: $profile.appearance.enabled)
            Group {
                Picker("Position", selection: $profile.appearance.orientation) {
                    ForEach(DockOrientation.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                LabeledContent("Size") {
                    Slider(value: $profile.appearance.tileSize, in: 16...128).frame(maxWidth: 280)
                }
                Toggle("Magnification", isOn: $profile.appearance.magnification)
                if profile.appearance.magnification {
                    LabeledContent("Magnified size") {
                        Slider(value: $profile.appearance.largeSize, in: 16...128).frame(maxWidth: 280)
                    }
                }
                Toggle("Automatically hide and show the Dock", isOn: $profile.appearance.autohide)
                Toggle("Show recent applications", isOn: $profile.appearance.showRecents)
                Toggle("Minimize windows into application icon", isOn: $profile.appearance.minimizeIntoIcon)
            }
            .disabled(!profile.appearance.enabled)
            .opacity(profile.appearance.enabled ? 1 : 0.45)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                showingIdentity = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: profile.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(profile.color.color)
                    Text(profile.name).font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    if store.activeProfileID == profile.id {
                        Text("Active now")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(titleHovering ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { titleHovering = $0 }
            .help("Rename this profile, or change its colour and glyph")
            .popover(isPresented: $showingIdentity, arrowEdge: .bottom) {
                ProfileIdentityPopover(profile: $profile)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                store.activate(profile.id)
            } label: {
                Label(
                    store.activeProfileID == profile.id ? "Re-apply" : "Activate",
                    systemImage: "arrow.right"
                )
                .labelStyle(.titleAndIcon)
            }
            .disabled(store.isApplying)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Rename, colour & glyph…") { showingIdentity = true }
                Divider()
                Button("Duplicate") { store.duplicate(profile.id) }
                Button("Capture my Dock") { store.captureCurrentDock(into: profile.id) }
                Divider()
                Button("Delete", role: .destructive) { store.delete(profile.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    // MARK: - Editing

    private func append(_ tile: DockTile?) {
        guard let tile else { return }
        tilesBinding.wrappedValue.append(tile)
    }

    private func removeSelection() {
        guard let selection else { return }
        tilesBinding.wrappedValue.removeAll { $0.id == selection }
        self.selection = nil
    }

    private func add(_ urls: [URL]) {
        var items = tiles
        for url in urls {
            if url.pathExtension == "app" || section == .apps {
                if let tile = DockTile.app(at: url) { items.append(tile) }
            } else if let tile = DockTile.folder(at: url) {
                items.append(tile)
            }
        }
        tilesBinding.wrappedValue = items
    }

    private func addFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = section == .others
        if section == .apps {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }
}

// MARK: - Item card

private struct ItemCard: View {
    let tile: DockTile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if tile.kind.isSpacer {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    )
            } else if let icon = tile.icon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "questionmark").font(.system(size: 12)))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(tile.label)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(tile.isMissing ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.10) }
        if tile.isMissing { return Color.orange.opacity(0.10) }
        return Color.primary.opacity(0.04)
    }

    private var subtitle: String {
        if tile.isMissing { return "Moved or deleted" }
        if tile.kind.isSpacer { return "Gap in the Dock" }
        guard let path = tile.path else { return "" }
        return (path as NSString).deletingLastPathComponent
    }
}

// MARK: - Name, colour and glyph

struct ProfileIdentityPopover: View {
    @Binding var profile: DockProfile
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Name", text: $profile.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($nameFocused)
                .task { nameFocused = true }

            VStack(alignment: .leading, spacing: 6) {
                Text("Colour").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(ProfileColor.allCases) { option in
                        Button {
                            profile.color = option
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle().strokeBorder(.primary, lineWidth: profile.color == option ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Glyph").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 28), spacing: 6), count: 6),
                    spacing: 6
                ) {
                    ForEach(ProfileSymbol.all, id: \.self) { symbol in
                        Button {
                            profile.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(profile.symbol == symbol ? profile.color.color.opacity(0.22) : Color.primary.opacity(0.05))
                                )
                                .foregroundStyle(profile.symbol == symbol ? profile.color.color : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
