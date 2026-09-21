import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum EditorTab: String, CaseIterable, Identifiable {
    case items, dock, customDock, widgets, desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .items: return "Items"
        case .dock: return "Dock"
        case .customDock: return "Custom Dock"
        case .widgets: return "Widgets"
        case .desktop: return "Desktop"
        }
    }
}

struct ProfileEditorView: View {
    @EnvironmentObject private var store: ProfileStore
    @Binding var profile: DockProfile

    @State private var tab: EditorTab = .items
    @State private var section: DockSection = .apps
    // Reordering in the Items list
    @State private var draggingCard: UUID?
    @State private var dragPoint: CGPoint = .zero
    @State private var cardFrames: [UUID: CGRect] = [:]
    /// The order as the drag has it so far; kept after the drop until the row catches up.
    @State private var pendingRow: [DockStripItem]?
    @State private var selection: UUID?
    @State private var keyMonitor: Any?
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
        .onAppear {
            installKeyMonitor()
            // A profile created a moment ago still has a placeholder name.
            if router.pendingRename == profile.id {
                router.pendingRename = nil
                showingIdentity = true
            }
            openCustomDockIfAsked()
        }
        // The editor may already be showing this profile when the dock asks for
        // its settings, in which case it never reappears.
        .onChange(of: router.pendingCustomDock) { _, _ in openCustomDockIfAsked() }
        .onDisappear(perform: removeKeyMonitor)
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
        if profile.customDock.isActive {
            text = text + Text(", shows its ")
                + Text(profile.customDock.mode == .combined ? "custom dock" : "widgets").bold()
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

    /// The row on show: apps (with the widgets among them when the custom dock is
    /// combined) or the folders side. Writing it back reorders, adds and removes.
    private var rowBinding: Binding<[DockStripItem]> {
        Binding(
            get: { section == .apps ? profile.appRow : profile.others.map { .tile($0) } },
            set: { row in
                if section == .apps {
                    profile.setAppRow(row)
                } else {
                    profile.others = row.compactMap(\.tile)
                }
            }
        )
    }

    private var row: [DockStripItem] { rowBinding.wrappedValue }
    private var tiles: [DockTile] { row.compactMap(\.tile) }

    /// What the Items list shows: the row — with a combined custom dock, widgets in
    /// among the apps as the dock has them — in the order a drag in progress has it.
    private var listedItems: [DockStripItem] { pendingRow ?? row }

    private var dockPreview: some View {
        DockPreviewStrip(
            items: rowBinding,
            selection: $selection,
            onAdd: addFromPanel,
            onDropURLs: add
        )
    }

    private var hintRow: some View {
        HStack {
            Text(
                profile.customDock.isCombined && section == .apps
                    ? "Drag apps and widgets to arrange your custom dock · right-click or ⌫ to remove · drop an app from Finder to add"
                    : "Drag to reorder · right-click or ⌫ to remove · drop an app from Finder to add"
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            Spacer()
            if let item = row.first(where: { $0.id == selection }) {
                Text(item.tile?.label ?? item.widget?.kind.title ?? "").font(.system(size: 12, weight: .medium))
                    + Text(" selected").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private func openCustomDockIfAsked() {
        guard router.pendingCustomDock == profile.id else { return }
        router.pendingCustomDock = nil
        tab = router.pendingWidgets ? .widgets : .customDock
        router.pendingWidgets = false
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
                        case .customDock:
                            dot(profile.customDock.isActive ? Color.accentColor : .clear)
                        case .widgets:
                            Text("\(profile.customDock.widgets.count)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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
            case .customDock: CustomDockOptionsView(options: $profile.customDock, tint: profile.color.color, part: .dock)
            case .widgets: CustomDockOptionsView(options: $profile.customDock, tint: profile.color.color, part: .widgets)
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
                if section == .apps {
                    // Click adds from a file panel; the arrow offers Finder, which lives
                    // in CoreServices where nobody goes looking, at the front as the
                    // Dock has it.
                    Menu {
                        Button("Finder") { addFinder() }
                            .disabled(profile.apps.contains { $0.isFinder })
                    } label: {
                        Text("Add app…")
                    } primaryAction: {
                        addFromPanel()
                    }
                    .fixedSize()
                } else {
                    Button("Add folder…", action: addFromPanel)
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
                itemsGrid
            }
        }
    }

    // MARK: - Items grid

    /// The cards, reordered by dragging one — a gesture like the live dock's rather
    /// than `onDrag`/`onDrop`: on macOS, drop targets inside a
    /// scrolled `ScrollView` are hit-tested at their unscrolled positions, so the cards
    /// further down the list — where the widgets tend to be — never accepted a drop.
    private var itemsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(listedItems) { item in
                card(item)
                    .background(CardFrameReporter(id: item.id))
                    // While held, the slot stays put — invisible — and the ghost follows the pointer.
                    .opacity(draggingCard == item.id ? 0 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = item.id }
                    .contextMenu {
                        Button("Remove from profile", role: .destructive) {
                            remove(item.id)
                        }
                    }
                    .simultaneousGesture(cardDragGesture(item))
            }
        }
        .overlay(cardGhost)
        .coordinateSpace(name: "items")
        .onPreferenceChange(CardFrameKey.self) { cardFrames = $0 }
        .onChange(of: row) { pendingRow = nil }
    }

    @ViewBuilder
    private func card(_ item: DockStripItem) -> some View {
        switch item {
        case .tile(let tile):
            ItemCard(tile: tile, isSelected: selection == item.id)
        case .widget(let widget):
            WidgetItemCard(widget: widget, isSelected: selection == item.id)
        }
    }

    @ViewBuilder
    private var cardGhost: some View {
        if let draggingCard, let item = listedItems.first(where: { $0.id == draggingCard }) {
            let slot = cardFrames[draggingCard] ?? .zero
            card(item)
                .frame(width: slot.width, height: slot.height)
                .scaleEffect(1.03)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .position(dragPoint)
                .allowsHitTesting(false)
                .transition(.identity)
        }
    }

    /// A card starts moving as soon as it is dragged a few points — no hold, unlike
    /// the live dock, where a hold keeps a click from turning into a drag. A click
    /// does not travel that far, so selecting still works.
    private func cardDragGesture(_ item: DockStripItem) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("items"))
            .onChanged { drag in
                if draggingCard != item.id {
                    draggingCard = item.id
                    selection = item.id
                    pendingRow = row
                }
                dragPoint = drag.location
                shuffleCards(item.id)
            }
            .onEnded { _ in endCardDrag() }
    }

    /// Moves the held card into the slot of whichever card the pointer is over —
    /// after it when moving down the list, before it when moving up.
    private func shuffleCards(_ id: UUID) {
        var order = listedItems
        guard let from = order.firstIndex(where: { $0.id == id }),
              let target = order.firstIndex(where: { $0.id != id && (cardFrames[$0.id]?.contains(dragPoint) ?? false) }),
              target != from else { return }
        let item = order.remove(at: from)
        order.insert(item, at: target)
        withAnimation(.easeInOut(duration: 0.15)) { pendingRow = order }
    }

    private func endCardDrag() {
        guard draggingCard != nil else { return }
        draggingCard = nil
        if let order = pendingRow, order.map(\.id) != row.map(\.id) {
            rowBinding.wrappedValue = order
        } else {
            pendingRow = nil
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
                PaneTitle(symbol: profile.symbol, tint: profile.color.color) {
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
                Button("Export…") { ProfileSharing.export([profile]) }
                Divider()
                Button("Delete", role: .destructive) { store.delete(profile.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    // MARK: - Keyboard

    /// ⌫ removes the selected tile and ⎋ clears the selection. Nothing in the editor
    /// takes keyboard focus of its own (SwiftUI's `focusable()` only works on macOS
    /// with keyboard navigation switched on), so the keys are picked up with a
    /// monitor instead, stepping aside whenever a text field is being edited.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let editingText = event.window?.firstResponder is NSTextView
            let hasModifiers = !event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.function)  // forward delete carries the fn flag
                .isEmpty
            let consumed = MainActor.assumeIsolated {
                handle(keyCode: keyCode, editingText: editingText, hasModifiers: hasModifiers)
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(keyCode: UInt16, editingText: Bool, hasModifiers: Bool) -> Bool {
        guard selection != nil, !editingText, !hasModifiers else { return false }
        switch Int(keyCode) {
        case 51, 117:  // ⌫, forward delete
            removeSelection()
            return true
        case 53:  // esc
            selection = nil
            return true
        default:
            return false
        }
    }

    // MARK: - Editing

    private func removeSelection() {
        guard let selection else { return }
        remove(selection)
    }

    private func remove(_ id: UUID) {
        rowBinding.wrappedValue.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    private func append(_ tile: DockTile?) {
        guard let tile else { return }
        rowBinding.wrappedValue.append(.tile(tile))
    }

    /// Adds files dropped or chosen, in front of `target` — or at the end without one.
    private func add(_ urls: [URL], before target: UUID? = nil) {
        var added: [DockStripItem] = []
        for url in urls where url.isFileURL {
            if url.pathExtension == "app" || section == .apps {
                if let tile = DockTile.app(at: url) { added.append(.tile(tile)) }
            } else if let tile = DockTile.folder(at: url) {
                added.append(.tile(tile))
            }
        }
        guard !added.isEmpty else { return }
        var items = row
        let index = target.flatMap { id in items.firstIndex { $0.id == id } } ?? items.endIndex
        items.insert(contentsOf: added, at: index)
        rowBinding.wrappedValue = items
    }

    /// Pins Finder at the front of the row, where the Dock keeps it.
    private func addFinder() {
        guard !profile.apps.contains(where: { $0.isFinder }), let finder = DockTile.finder else { return }
        var items = row
        items.insert(.tile(finder), at: 0)
        rowBinding.wrappedValue = items
        selection = finder.id
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

/// A widget's place in the Items list when the custom dock is combined. Its
/// settings live on the Custom dock tab; here it is a row to arrange among the apps.
private struct WidgetItemCard: View {
    let widget: WidgetTile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(
                    WidgetKindIcon(kind: widget.kind, size: 12)
                        .foregroundStyle(Color.accentColor)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(widget.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text("Widget · \(widget.summary)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
    }
}

/// Where each card sits in the grid, for the reorder gesture.
private struct CardFrameReporter: View {
    let id: UUID

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: CardFrameKey.self, value: [id: geometry.frame(in: .named("items"))])
        }
    }
}

private struct CardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

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
