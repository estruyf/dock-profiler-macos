import AppKit
import SwiftUI

/// The custom-dock half of a profile, on two tabs: the dock itself — what it
/// shows, where it sits, how it looks — and its widgets.
struct CustomDockOptionsView: View {
    enum Part {
        case dock
        case widgets
    }

    @Binding var options: CustomDockOptions
    /// The profile's colour, for the tinted look and its preview.
    var tint: Color = .blue
    var part: Part = .dock

    @ObservedObject private var accessibility = AccessibilityDisplay.shared
    @ObservedObject private var badges = DockBadgeMonitor.shared
    /// The displays connected right now, for the per-display positions.
    @State private var screens = NSScreen.screens

    /// The widget cards open to their settings; the rest show a line each.
    @State private var expanded: Set<UUID> = []
    /// A card held by its header and carried down the list.
    @State private var draggingCard: UUID?
    @State private var cardPoint: CGPoint = .zero
    @State private var cardFrames: [UUID: CGRect] = [:]
    /// The order as the drag has it so far; kept after the drop until `options` catches up.
    @State private var pendingWidgets: [WidgetTile]?
    /// The stack card a held launcher is over: letting go folds it in.
    @State private var cardTarget: UUID?
    /// A double-click or a right-click on a widget in the dock asks for that
    /// widget's card, which is opened and scrolled to as the tab appears.
    @ObservedObject private var router = WindowRouter.shared

    /// Width of the label column, so pickers and sliders line up down the form.
    private let labelWidth: CGFloat = 104

    var body: some View {
        switch part {
        case .dock: dockPart
        case .widgets: widgetsPart
        }
    }

    private var dockPart: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show a custom dock when this profile is activated", isOn: $options.enabled)
                Text("The macOS Dock has no room for widgets, so Dock Profiler draws a dock of its own. It follows whichever profile is active and never takes focus from what you are doing. Its widgets are on the Widgets tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                section("Layout") { layoutSection }
                section("Position") { positionSection }
                section("Style") { styleSection }
                section("Size") { sizeSection }
            }
            .disabled(!options.enabled)
            .opacity(options.enabled ? 1 : 0.45)
        }
        .onAppear { badges.refreshTrust() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }

    // MARK: - Form scaffolding

    /// A titled group of rows, ruled off from the one before it.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// A label in the left column and a control in the right, as System Settings lays them out.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(width: labelWidth, alignment: .trailing)
            content()
        }
    }

    /// A row with nothing in the label column: toggles and captions sit under the controls.
    private func indented<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear.frame(width: labelWidth, height: 1)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A slider in whole points, without the tick marks a stepped slider draws.
    private func sizeSlider(_ value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        let stepped = Binding<Double>(
            get: { value.wrappedValue },
            set: { value.wrappedValue = (($0 / 2).rounded() * 2).clamped(to: range) }
        )
        return HStack(spacing: 10) {
            Slider(value: stepped, in: range).frame(maxWidth: 280)
            Text("\(Int(value.wrappedValue)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
        }
    }

    // MARK: - Layout

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Show") {
                Picker("Show", selection: $options.mode) {
                    ForEach(CustomDockMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            indented {
                VStack(alignment: .leading, spacing: 8) {
                    switch options.mode {
                    case .combined:
                        caption("Your apps and widgets in one dock — arrange them in the preview above. The macOS Dock hides itself while this profile is active, and comes back with the next profile that does not stand in for it.")
                        Toggle("Also show apps that are open but not in the profile", isOn: $options.showsRunningApps)
                        Toggle("Show notification badges on app tiles", isOn: $options.showsBadges)
                            .onChange(of: options.showsBadges) { _, on in
                                if on { badges.requestAccess() }
                            }
                        if options.showsBadges {
                            if badges.isTrusted {
                                caption("Badges are read from the macOS Dock through Accessibility, which Dock Profiler has been granted.")
                            } else {
                                caption("Badges are read from the macOS Dock, which takes Accessibility access. Allow Dock Profiler under Privacy & Security → Accessibility; the badges appear once it is granted.")
                                Button("Open Accessibility Settings…") { DockBadgeMonitor.openAccessibilitySettings() }
                                    .controlSize(.small)
                            }
                        }
                    case .detached:
                        caption("A strip of widgets on its own, beside the macOS Dock.")
                    }
                }
            }
        }
    }

    // MARK: - Position

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    row("Edge") {
                        Picker("Edge", selection: $options.edge) {
                            ForEach(DockStripEdge.allCases) { edge in
                                Text(edge.title).tag(edge)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }
                    row("Align") {
                        if options.edge.isVertical {
                            Text("Centred along the \(options.edge.title.lowercased()) edge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(height: 22)
                        } else {
                            Picker("Align", selection: $options.alignment) {
                                ForEach(DockStripAlignment.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                    }
                }
                ScreenDiagram(edge: options.edge, alignment: options.alignment)
                    .padding(.top, 2)
            }
            row("Showing") {
                Picker("Showing", selection: $options.visibility) {
                    ForEach(DockVisibility.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            indented {
                VStack(alignment: .leading, spacing: 6) {
                    caption(options.visibility.summary)
                    if options.visibility == .autohide {
                        Toggle("Leave a mark on the edge while it is hidden", isOn: $options.edgeHint)
                    }
                }
            }
            row("Sits") {
                Picker("Sits", selection: $options.attachment) {
                    ForEach(DockAttachment.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            indented {
                caption(options.attachment.summary)
            }
            row("Displays") {
                Picker("Displays", selection: $options.displays) {
                    ForEach(DockDisplays.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            indented {
                VStack(alignment: .leading, spacing: 8) {
                    switch options.displays {
                    case .main:
                        caption("On the display with the menu bar, where the macOS Dock lives.")
                    case .all:
                        caption("A dock on every display. Each takes the position above unless it is given one of its own — so two displays side by side can keep their docks on the outer edges, leaving the edge between them clear for the pointer.")
                        if screens.count > 1 {
                            displayList
                        } else {
                            caption("Only one display is connected right now. Others take the position above when they are plugged in, until they are given one here.")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Per-display positions

    /// One row per connected display, each taking the position above until it is
    /// given an edge and alignment of its own.
    private var displayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(screens, id: \.displayKey) { screen in
                DisplayPlacementRow(
                    name: screen.localizedName,
                    isMain: screen.isMain,
                    shared: options.placement,
                    own: ownPlacement(for: screen)
                )
            }
        }
        .padding(.top, 2)
    }

    /// The display's own position, or nil while it takes the shared one. Setting
    /// it starts from the shared position, so turning it on changes nothing until
    /// a picker does.
    private func ownPlacement(for screen: NSScreen) -> Binding<DockPlacement?> {
        let key = screen.displayKey
        return Binding(
            get: { options.displayPlacements[key] },
            set: { options.displayPlacements[key] = $0 }
        )
    }

    // MARK: - Style

    private var styleSection: some View {
        let hasPlate = options.look.style.hasPlate
        return VStack(alignment: .leading, spacing: 8) {
            row("Look") {
                Picker("Look", selection: $options.look.style) {
                    ForEach(DockStyle.available) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            indented {
                caption(styleCaption)
            }
            row("Density") {
                Picker("Density", selection: $options.look.density) {
                    ForEach(DockDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            indented {
                VStack(alignment: .leading, spacing: 8) {
                    // Without a slab there is nothing to blur or tint, and the cards
                    // are what hold a widget together.
                    Toggle("Blur what is behind it", isOn: $options.look.translucent)
                        .disabled(!hasPlate)
                    if hasPlate, options.look.style == .liquidGlass, !options.look.translucent {
                        caption("Clear glass: it still refracts what is behind it, without frosting it — dimmed a little so the tiles stay readable.")
                    } else if hasPlate, !options.look.translucent {
                        caption("Solid: nothing shows through.")
                    }
                    if hasPlate, accessibility.reducesTransparency {
                        caption("Reduce transparency is on in System Settings → Accessibility, so the dock is drawn solid for now.")
                    }
                    Toggle("Tint with the profile's colour", isOn: $options.look.tinted)
                        .disabled(!hasPlate)
                    Toggle("Cards behind widgets", isOn: Binding(
                        get: { options.look.drawsTileCards },
                        set: { options.look.tileCards = $0 }
                    ))
                    .disabled(!hasPlate)
                    Toggle("Open a widget's card when the pointer rests on it", isOn: $options.hoverCards)
                    caption("The card a click opens — a stack's files, the sessions, a service's usage — slides out on its own after a moment, and goes away when the pointer leaves it. A click still opens it at once, and pins it.")
                }
            }
        }
    }

    private var styleCaption: String {
        if options.look.style == .liquidGlass, !DockStyle.supportsLiquidGlass {
            return "Liquid Glass needs macOS Tahoe; on this Mac the dock follows the system instead."
        }
        return options.look.style.summary + "."
    }

    // MARK: - Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Tile size") {
                sizeSlider($options.tileSize, in: 36...96)
            }
            indented {
                Toggle("Magnify tiles under the pointer", isOn: $options.magnification)
            }
            if options.magnification {
                row("Magnified size") {
                    sizeSlider($options.magnifiedSize, in: 40...128)
                }
            }
            row(options.edge.isVertical ? "Maximum height" : "Maximum width") {
                HStack(spacing: 10) {
                    Text(options.maxLength.map { "\(Int($0)) pt" } ?? "As much as the screen has room for")
                        .monospacedDigit()
                    if options.maxLength != nil {
                        Button("Use the Whole Screen") { options.maxLength = nil }
                            .controlSize(.small)
                    }
                }
            }
            indented {
                caption("Drag the grip at the end of the dock to limit it. Past the limit — or the screen's edge — the tiles page, with arrows at the end of the dock to move through them.")
            }
        }
    }

    // MARK: - Widgets

    /// The widgets tab: what to add at the top, then a card per widget, folded to
    /// a line each until opened, with the strip's preview where the dock is
    /// widgets alone. Cards are carried by their headers: down the list to
    /// reorder, or a launcher onto a stack to fold it in.
    private var widgetsPart: some View {
        // Inside the editor's own scroll view: the reader finds it and scrolls it
        // to the card the dock asked for.
        ScrollViewReader { proxy in
            widgetsList
                .onAppear { revealRequestedWidget(proxy) }
                .onChange(of: router.pendingWidgetID) { revealRequestedWidget(proxy) }
        }
    }

    /// Opens the card the dock asked for and brings it into view. A widget with no
    /// settings — a divider — is only scrolled to; there is nothing to unfold.
    private func revealRequestedWidget(_ proxy: ScrollViewProxy) {
        guard let id = router.pendingWidgetID else { return }
        guard let widget = options.widgets.first(where: { $0.id == id }) else { return }
        router.pendingWidgetID = nil
        if widget.kind.isConfigurable { expanded.insert(id) }
        // After the tab has laid out, or there is nothing to scroll to yet.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
        }
    }

    private var widgetsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !options.enabled {
                HStack(spacing: 10) {
                    Text("The custom dock is off for this profile, so its widgets are not shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Turn On") { options.enabled = true }
                        .controlSize(.small)
                }
            }
            widgetsHeader
            if options.widgets.isEmpty {
                emptyState
            } else if options.mode == .detached {
                previewAndCards
            } else {
                cards
            }
            if options.widgets.count > 2 {
                addWidgetMenu("Add widget")
            }
        }
        .disabled(!options.enabled)
        .opacity(options.enabled ? 1 : 0.45)
    }

    private var widgetsHeader: some View {
        HStack(spacing: 8) {
            Text("Widgets")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if !options.widgets.isEmpty {
                Text("\(options.widgets.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
            if !options.widgets.isEmpty {
                caption(options.mode == .detached
                    ? "Click a card to open its settings · drag a card by its header to reorder"
                    : "Click a card to open its settings · arrange the tiles in the Items tab")
            }
            addWidgetMenu("Add widget")
        }
    }

    private func addWidgetMenu(_ title: String) -> some View {
        Menu(title) {
            ForEach(WidgetGroup.all) { group in
                ForEach(group.kinds) { kind in
                    Button {
                        let widget = WidgetTile(kind: kind)
                        options.widgets.append(widget)
                        if kind.isConfigurable { expanded.insert(widget.id) }
                    } label: {
                        if let image = WidgetKindIcon.menuImage(for: kind) {
                            Label { Text(kind.title) } icon: { Image(nsImage: image) }
                        } else {
                            Label(kind.title, systemImage: kind.symbolName)
                        }
                    }
                }
                if group.id != WidgetGroup.all.last?.id { Divider() }
            }
        }
        .fixedSize()
    }

    /// The preview sits where the dock will: beside the cards for a left or right
    /// edge, above or below them for top or bottom. A column of widgets no longer
    /// pushes the cards off the bottom of the window.
    @ViewBuilder
    private var previewAndCards: some View {
        switch options.edge {
        case .top:
            VStack(alignment: .leading, spacing: 12) { preview; cards }
        case .bottom:
            VStack(alignment: .leading, spacing: 12) { cards; preview }
        case .leading:
            HStack(alignment: .top, spacing: 16) { preview; cards }
        case .trailing:
            HStack(alignment: .top, spacing: 16) { cards; preview }
        }
    }

    /// The cards in the order a drag in progress has them.
    private var listedWidgets: [WidgetTile] { pendingWidgets ?? options.widgets }

    private var cards: some View {
        // One card per line: two abreast left the settings on the wide cards cramped.
        LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(Array(listedWidgets.enumerated()), id: \.element.id) { index, tile in
                WidgetSettingsCard(
                    tile: binding(for: tile.id),
                    isExpanded: isExpanded(tile.id),
                    isTargeted: cardTarget == tile.id,
                    headerGesture: AnyGesture(cardDragGesture(tile.id).map { _ in () }),
                    onRemove: { options.widgets.removeAll { $0.id == tile.id } },
                    onMoveOut: { launcher in moveOut(launcher, of: tile.id) }
                ) {
                    // On the header alone: a menu over the whole card would take the
                    // right-click from the entries of a stack, which have menus of their own.
                    // In a combined dock the order lives in the Items tab.
                    if options.mode == .detached {
                        Button("Move up") { move(index, by: -1) }
                            .disabled(index == 0)
                        Button("Move down") { move(index, by: 1) }
                            .disabled(index == options.widgets.count - 1)
                        Divider()
                    }
                    if tile.kind == .launcher {
                        let stacks = options.widgets.filter { $0.kind == .appStack }
                        if !stacks.isEmpty {
                            Menu("Move into Stack") {
                                ForEach(stacks) { stack in
                                    Button(stack.stack.isEmpty ? "App Stack" : stack.summary) { moveIn(tile.id, to: stack.id) }
                                }
                            }
                            Divider()
                        }
                    }
                    Button("Remove from profile", role: .destructive) {
                        options.widgets.removeAll { $0.id == tile.id }
                    }
                }
                .id(tile.id)
                .background(WidgetCardFrameReporter(id: tile.id))
                // While held, the slot stays put — invisible — and the ghost follows the pointer.
                .opacity(draggingCard == tile.id ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(cardGhost)
        .coordinateSpace(name: "widgets")
        .onPreferenceChange(WidgetCardFrameKey.self) { cardFrames = $0 }
        .onChange(of: options.widgets) { pendingWidgets = nil }
    }

    /// The held card, folded to its header, under the pointer.
    @ViewBuilder
    private var cardGhost: some View {
        if let draggingCard, let tile = listedWidgets.first(where: { $0.id == draggingCard }) {
            let slot = cardFrames[draggingCard] ?? .zero
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                    .overlay(WidgetKindIcon(kind: tile.kind, size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title).font(.system(size: 13))
                    Text(cardTarget != nil ? "Add to stack" : tile.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: slot.width)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .position(x: slot.midX, y: cardPoint.y)
            .allowsHitTesting(false)
            .transition(.identity)
        }
    }

    private func cardDragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("widgets"))
            .onChanged { drag in
                if draggingCard != id {
                    draggingCard = id
                    pendingWidgets = options.widgets
                    cardTarget = nil
                }
                cardPoint = drag.location
                shuffleCards(id)
            }
            .onEnded { _ in endCardDrag() }
    }

    /// Puts the held card where the pointer is — or, for a launcher over a stack
    /// card, holds still and marks the stack.
    private func shuffleCards(_ id: UUID) {
        guard let held = listedWidgets.first(where: { $0.id == id }) else { return }
        if held.kind == .launcher,
           let stack = listedWidgets.first(where: { $0.kind == .appStack && (cardFrames[$0.id]?.contains(cardPoint) ?? false) }) {
            cardTarget = stack.id
            return
        }
        cardTarget = nil
        // A combined dock orders its widgets among the apps, in the Items tab.
        guard options.mode == .detached else { return }
        var order = listedWidgets.filter { $0.id != id }
        guard let under = order.firstIndex(where: { cardFrames[$0.id]?.contains(cardPoint) ?? false }) else { return }
        order.insert(held, at: under)
        guard order.map(\.id) != listedWidgets.map(\.id) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { pendingWidgets = order }
    }

    private func endCardDrag() {
        guard let id = draggingCard else { return }
        draggingCard = nil
        if let target = cardTarget {
            cardTarget = nil
            pendingWidgets = nil
            moveIn(id, to: target)
            return
        }
        if let order = pendingWidgets, order.map(\.id) != options.widgets.map(\.id) {
            options.widgets = order
        } else {
            pendingWidgets = nil
        }
    }

    private func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in if open { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }

    /// The strip exactly as it will appear beside the Dock, magnification included.
    private var preview: some View {
        let strip = CustomDockView(
            items: options.widgets.map { .widget($0) },
            edge: options.edge,
            tileSize: options.tileSize,
            magnificationExtra: options.magnificationExtra,
            look: options.look,
            tint: tint,
            flatEdge: options.attachment == .attached ? options.edge : nil,
            onReorder: { options.widgets = $0.compactMap(\.widget) }
        )
        return Group {
            if options.edge.isVertical {
                strip
            } else {
                HStack {
                    if options.alignment != .leading { Spacer() }
                    strip
                    if options.alignment != .trailing { Spacer() }
                }
            }
        }
        .padding(.vertical, 4)
        // A stack opened from the preview can be rearranged there too.
        .environment(\.dockWidgetUpdate) { widget in
            guard let index = options.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
            options.widgets[index] = widget
        }
        .environment(\.dockStackMoveOut) { entry, stackID in
            guard let index = options.widgets.firstIndex(where: { $0.id == stackID }) else { return }
            options.widgets[index].stack.removeAll { $0.id == entry.id }
            let launcher: WidgetTile
            switch entry {
            case .launcher(let existing): launcher = existing
            case .app(let app):
                guard let path = app.path else { return }
                var made = WidgetTile(kind: .launcher)
                made.path = path
                launcher = made
            }
            moveOut(launcher, of: stackID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(options.mode == .combined ? "No widgets among your apps yet" : "No widgets yet")
                .font(.system(size: 13, weight: .medium))
            Text("A clock, the Trash, AirDrop, a folder, a stack of apps, an app opened with arguments of your own, what is playing, your batteries, your profiles, your coding agents or your AI usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            addWidgetMenu("Add a widget")
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.primary.opacity(0.15))
        )
    }

    /// A binding to one widget by id, so a card's settings write straight back to the profile.
    private func binding(for id: UUID) -> Binding<WidgetTile> {
        Binding(
            get: { options.widgets.first { $0.id == id } ?? WidgetTile(kind: .clock) },
            set: { updated in
                guard let index = options.widgets.firstIndex(where: { $0.id == id }) else { return }
                options.widgets[index] = updated
            }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard options.widgets.indices.contains(target) else { return }
        options.widgets.swapAt(index, target)
    }

    /// Folds a launcher widget into a stack, at its end; the widget is gone from the row.
    private func moveIn(_ id: UUID, to stackID: UUID) {
        guard let launcher = options.widgets.first(where: { $0.id == id }),
              let index = options.widgets.firstIndex(where: { $0.id == stackID }) else { return }
        options.widgets[index].stack.append(.launcher(launcher))
        options.widgets.removeAll { $0.id == id }
    }

    /// Puts a launcher taken out of a stack right after the stack: the same anchor,
    /// next in the list, so a combined dock puts it there too.
    private func moveOut(_ launcher: WidgetTile, of stackID: UUID) {
        guard let index = options.widgets.firstIndex(where: { $0.id == stackID }) else { return }
        var widget = launcher
        widget.anchor = options.widgets[index].anchor
        options.widgets[index].stack.removeAll { $0.id == launcher.id }
        options.widgets.insert(widget, at: index + 1)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct WidgetCardFrameReporter: View {
    let id: UUID

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: WidgetCardFrameKey.self, value: [id: geometry.frame(in: .named("widgets"))])
        }
    }
}

private struct WidgetCardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A connected display and where its dock sits: the shared position, or one of
/// its own with its edge and alignment pickers and a diagram of the result.
private struct DisplayPlacementRow: View {
    let name: String
    let isMain: Bool
    /// The position every display takes unless it has its own.
    let shared: DockPlacement
    @Binding var own: DockPlacement?

    private var placement: DockPlacement { own ?? shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isMain ? "menubar.dock.rectangle" : "display")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                if isMain {
                    Text("Main")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                Toggle("Its own position", isOn: Binding(
                    get: { own != nil },
                    set: { own = $0 ? shared : nil }
                ))
                .controlSize(.small)
            }
            if own != nil {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Edge")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            Picker("Edge", selection: edge) {
                                ForEach(DockStripEdge.allCases) { edge in
                                    Text(edge.title).tag(edge)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .controlSize(.small)
                            .frame(maxWidth: 260)
                        }
                        HStack(spacing: 8) {
                            Text("Align")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            if placement.edge.isVertical {
                                Text("Centred along the \(placement.edge.title.lowercased()) edge")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(height: 20)
                            } else {
                                Picker("Align", selection: alignment) {
                                    ForEach(DockStripAlignment.allCases) { value in
                                        Text(value.title).tag(value)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(maxWidth: 200)
                            }
                        }
                    }
                    ScreenDiagram(edge: placement.edge, alignment: placement.alignment)
                }
                .padding(.leading, 24)
            } else {
                Text(isMain ? "The position above" : "The position above — \(shared.title.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var edge: Binding<DockStripEdge> {
        Binding(get: { placement.edge }, set: { own = DockPlacement(edge: $0, alignment: placement.alignment) })
    }

    private var alignment: Binding<DockStripAlignment> {
        Binding(get: { placement.alignment }, set: { own = DockPlacement(edge: placement.edge, alignment: $0) })
    }
}

/// A thumbnail of the screen with the dock drawn on its chosen edge, so the
/// edge and alignment pickers show what they mean.
private struct ScreenDiagram: View {
    let edge: DockStripEdge
    let alignment: DockStripAlignment

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
            .overlay(alignment: anchor) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: edge.isVertical ? 6 : 30, height: edge.isVertical ? 22 : 6)
                    .padding(3)
            }
            .frame(width: 76, height: 50)
            .animation(.snappy(duration: 0.2), value: edge)
            .animation(.snappy(duration: 0.2), value: alignment)
            .accessibilityLabel("Dock on the \(edge.title.lowercased()) edge")
    }

    private var anchor: Alignment {
        switch edge {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top:
            switch alignment {
            case .leading: return .topLeading
            case .center: return .top
            case .trailing: return .topTrailing
            }
        case .bottom:
            switch alignment {
            case .leading: return .bottomLeading
            case .center: return .bottom
            case .trailing: return .bottomTrailing
            }
        }
    }
}

/// One widget's card: a line with its icon, name and summary, that opens on a
/// click to the widget's settings when it has any. The header is the handle for
/// dragging the card.
private struct WidgetSettingsCard<HeaderMenu: View>: View {
    @Binding var tile: WidgetTile
    @Binding var isExpanded: Bool
    /// A held launcher is over this stack card.
    var isTargeted = false
    let headerGesture: AnyGesture<Void>
    let onRemove: () -> Void
    /// For an app stack: an entry taken out of it, to stand on its own after it.
    let onMoveOut: (WidgetTile) -> Void
    /// The card's own context menu, on its header.
    @ViewBuilder let headerMenu: () -> HeaderMenu

    @State private var hovering = false
    /// For the accessories card: the devices to tick, read while the card is on screen.
    @ObservedObject private var accessories = AccessoryBatteryMonitor.shared
    @ObservedObject private var macBattery = BatteryMonitor.shared
    /// For the app stack card: the launcher whose settings are open under the row.
    @State private var editingEntry: UUID?
    /// For the app stack card: an entry held and carried along the row, or off it.
    @State private var draggingEntry: UUID?
    @State private var entryPoint: CGPoint = .zero
    @State private var entryFrames: [UUID: CGRect] = [:]
    @State private var pendingStack: [AppStackEntry]?
    @State private var rowSize: CGSize = .zero

    private var isOpen: Bool { tile.kind.isConfigurable && isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isOpen {
                settings
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.10 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
        )
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 28, height: 28)
                .overlay(WidgetKindIcon(kind: tile.kind, size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title)
                    .font(.system(size: 13))
                Text(tile.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // A path keeps its ends; a sentence keeps its start.
                    .truncationMode(tile.kind == .folderStack ? .middle : .tail)
            }
            Spacer(minLength: 0)
            if tile.kind.isConfigurable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.15), value: isExpanded)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove from profile")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard tile.kind.isConfigurable else { return }
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        }
        .contextMenu { headerMenu() }
        .simultaneousGesture(headerGesture)
    }

    // MARK: - Settings

    @ViewBuilder
    private var settings: some View {
        switch tile.kind {
        case .folderStack:
            Button("Choose Folder…", action: chooseFolder)
                .controlSize(.small)
        case .appStack:
            appList
        case .launcher:
            LauncherFields(tile: $tile)
        case .agents:
            VStack(alignment: .leading, spacing: 6) {
                Picker("Layout", selection: $tile.agentsLayout) {
                    ForEach(AgentsLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 220)
                Toggle("Find the sessions running on this Mac", isOn: $tile.agentsFindsRunning)
                Text(tile.agentsFindsRunning
                     ? "Claude Code and Codex sessions are found by their own processes, so there is nothing to install. Those say working or idle — only Agent Frame's hooks know when a session is waiting for you, and its sessions are used wherever it has them."
                     : "Only the sessions Agent Frame reports, which alone say when one is waiting for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .accessories:
            accessorySettings
        case .nowPlaying:
            nowPlayingSettings
        case .aiUsage:
            usageSettings
        default:
            EmptyView()
        }
    }

    /// How much of the track is drawn, and whether the buttons sit beside it. The
    /// widget is only as wide as its layout lets it be, so a long title crops
    /// instead of pushing the rest of the dock along.
    private var nowPlayingSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Layout", selection: $tile.nowPlayingLayout) {
                ForEach(NowPlayingLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 220)
            Toggle("Show previous and next buttons", isOn: $tile.showsControls)
                .controlSize(.small)
            Text(nowPlayingHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nowPlayingHint: String {
        switch tile.nowPlayingLayout {
        case .full: return "The title and the artist beside the art, cropped once the title runs long. The whole track is in the tooltip."
        case .compact: return "The title alone beside the art, on one line. The artist is in the tooltip."
        case .artwork: return "The art alone, a tile the size of an app icon. The track is in the tooltip."
        }
    }

    /// How each battery is drawn, and which of them to show: every accessory that
    /// reports its charge, ticked off one by one, and this Mac's own if wanted.
    private var accessorySettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Layout", selection: $tile.accessoryLayout) {
                ForEach(AccessoryLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 220)
            if macBattery.status != nil {
                Toggle("This Mac", isOn: $tile.showsMacBattery)
                    .controlSize(.small)
            }
            ForEach(accessories.devices) { device in
                Toggle(isOn: shows(device.id)) {
                    HStack(spacing: 4) {
                        Text(device.name)
                        Text("\(device.level)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .controlSize(.small)
            }
            Text(accessories.devices.isEmpty
                 ? "No accessory is reporting its charge right now. Apple's report it to macOS; others, like a Logitech mouse, over Bluetooth — macOS asks once whether Dock Profiler may use it. They appear here as they connect."
                 : "Accessories appear here as they connect, and are shown unless ticked off. Apple's report their charge to macOS; others over Bluetooth, which macOS asks about once.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if accessories.bluetoothDenied {
                HStack(spacing: 8) {
                    Text("Bluetooth access is off, so accessories from other makers cannot report their charge.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings", action: AccessoryBatteryMonitor.openBluetoothPrivacySettings)
                        .controlSize(.small)
                }
            }
        }
        .onAppear { accessories.retain() }
        .onDisappear { accessories.release() }
    }

    private func shows(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !tile.hiddenAccessoryIDs.contains(id) },
            set: { on in
                if on {
                    tile.hiddenAccessoryIDs.removeAll { $0 == id }
                } else if !tile.hiddenAccessoryIDs.contains(id) {
                    tile.hiddenAccessoryIDs.append(id)
                }
            }
        )
    }

    /// How the allowances are drawn, and which services to track.
    private var usageSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Layout", selection: $tile.usageLayout) {
                ForEach(UsageLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 220)
            HStack(spacing: 8) {
                Text("Show")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Show", selection: $tile.usageMeasure) {
                    ForEach(UsageMeasure.allCases) { measure in
                        Text(measure.title).tag(measure)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 140)
                Text(tile.usageMeasure == .left
                     ? "What is still there. The ring fills as the allowance goes."
                     : "What has gone. The ring fills as the allowance is spent; its colour still says how much is left.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                ForEach(UsageService.allCases) { service in
                    Toggle(service.title, isOn: tracks(service))
                        .controlSize(.small)
                }
            }
            Text("Each tile shows the lowest remaining allowance in the main usage windows.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ticking a service on puts it back in its usual place among the others.
    private func tracks(_ service: UsageService) -> Binding<Bool> {
        Binding(
            get: { tile.usageServices.contains(service) },
            set: { on in
                if on {
                    tile.usageServices = UsageService.allCases.filter { $0 == service || tile.usageServices.contains($0) }
                } else {
                    tile.usageServices.removeAll { $0 == service }
                }
            }
        )
    }

    /// The stack's apps and launchers as a row of icons, with buttons to add an
    /// app or a launcher. Apps dropped from Finder land here too. Click a
    /// launcher to set it up under the row; right-click an entry to take it out,
    /// make a launcher of an app, or move a launcher out to stand on its own.
    private var appList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(listedStack) { entry in
                    stackIcon(entry)
                        .background(StackEntryFrameReporter(id: entry.id))
                        .opacity(draggingEntry == entry.id ? 0 : 1)
                        .simultaneousGesture(entryDragGesture(entry.id))
                }
                Button(tile.stack.isEmpty ? "Add Apps…" : "Add…", action: chooseApps)
                    .controlSize(.small)
                Button("Add Launcher", action: addLauncher)
                    .controlSize(.small)
            }
            .background(GeometryReader { geometry in
                Color.clear.onAppear { rowSize = geometry.size }.onChange(of: geometry.size) { _, size in rowSize = size }
            })
            .coordinateSpace(name: "stack")
            .onPreferenceChange(StackEntryFrameKey.self) { entryFrames = $0 }
            .onChange(of: tile.stack) { pendingStack = nil }
            .overlay(entryGhost)
            if let id = editingEntry, let index = tile.stack.firstIndex(where: { $0.id == id }) {
                let entry = tile.stack[index]
                VStack(alignment: .leading, spacing: 8) {
                    if entry.launcher != nil {
                        LauncherFields(tile: launcherBinding(at: index))
                    }
                    // What can be done with the entry, in plain sight.
                    HStack(spacing: 8) {
                        if entry.launcher == nil {
                            Text(entry.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("Make a Launcher") { tile.makeLauncher(of: entry.id) }
                                .controlSize(.small)
                        }
                        Button("Move Out of Stack") { moveOut(entry) }
                            .controlSize(.small)
                        Button("Remove from Stack", role: .destructive) { remove(entry) }
                            .controlSize(.small)
                        Spacer(minLength: 0)
                        Button {
                            editingEntry = nil
                        } label: {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Done")
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        }
    }

    /// Takes the entry out of the stack to stand on its own beside it: a launcher
    /// as it is, an app as a launcher of it — a tile that opens the app as an app
    /// tile does, ready for arguments and an icon.
    private func moveOut(_ entry: AppStackEntry) {
        let launcher: WidgetTile
        switch entry {
        case .launcher(let existing):
            launcher = existing
        case .app(let app):
            guard let path = app.path else { return }
            var made = WidgetTile(kind: .launcher)
            made.path = path
            launcher = made
        }
        if editingEntry == entry.id { editingEntry = nil }
        tile.stack.removeAll { $0.id == entry.id }
        onMoveOut(launcher)
    }

    private func remove(_ entry: AppStackEntry) {
        tile.stack.removeAll { $0.id == entry.id }
        if editingEntry == entry.id { editingEntry = nil }
    }

    private func stackIcon(_ entry: AppStackEntry) -> some View {
        let isLauncher = entry.launcher != nil
        let editing = editingEntry == entry.id
        return Group {
            if let image = entry.image {
                BadgedIcon(image: image, badge: entry.badge(side: 22), side: 22, ring: Color(nsColor: .windowBackgroundColor))
            } else {
                Image(systemName: isLauncher ? "arrow.up.forward.app" : "app.dashed").foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(editing ? 0.25 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { editingEntry = editing ? nil : entry.id }
        .help(isLauncher ? "\(entry.title) — click to set up" : "\(entry.title) — click for what can be done with it")
        .contextMenu {
            if isLauncher {
                Button(editing ? "Done" : "Set Up…") { editingEntry = editing ? nil : entry.id }
            } else {
                Button("Make a Launcher") {
                    tile.makeLauncher(of: entry.id)
                    editingEntry = entry.id
                }
            }
            Button("Move Out of Stack") { moveOut(entry) }
            Divider()
            Button("Remove \(entry.title)", role: .destructive) { remove(entry) }
        }
    }

    /// The row in the order a drag in progress has it.
    private var listedStack: [AppStackEntry] { pendingStack ?? tile.stack }

    /// A held entry is well off the row: letting go takes it out of the stack to
    /// stand on its own.
    private var entryOut: Bool {
        entryPoint.y < -24 || entryPoint.y > rowSize.height + 24
    }

    /// The held entry's icon under the pointer, with a word on what letting go does.
    @ViewBuilder
    private var entryGhost: some View {
        if let draggingEntry, let entry = listedStack.first(where: { $0.id == draggingEntry }) {
            let out = entryOut
            Group {
                if let image = entry.image {
                    BadgedIcon(image: image, badge: entry.badge(side: 22), side: 22, ring: Color(nsColor: .windowBackgroundColor))
                } else {
                    Image(systemName: "app.dashed").foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .scaleEffect(1.15)
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
            .overlay(alignment: .bottom) {
                if out {
                    Text("Out of stack")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.75)))
                        .fixedSize()
                        .offset(y: 18)
                }
            }
            .position(entryPoint)
            .allowsHitTesting(false)
        }
    }

    private func entryDragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("stack"))
            .onChanged { drag in
                if draggingEntry != id {
                    draggingEntry = id
                    pendingStack = tile.stack
                }
                entryPoint = drag.location
                shuffleEntries(id)
            }
            .onEnded { _ in endEntryDrag() }
    }

    /// Puts the held entry after every other whose centre the pointer has passed;
    /// off the row, its slot closes.
    private func shuffleEntries(_ id: UUID) {
        guard let held = listedStack.first(where: { $0.id == id }) else { return }
        var order = listedStack.filter { $0.id != id }
        if !entryOut {
            let target = order.filter { (entryFrames[$0.id]?.midX ?? .infinity) < entryPoint.x }.count
            order.insert(held, at: target)
        }
        guard order.map(\.id) != listedStack.map(\.id) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { pendingStack = order }
    }

    private func endEntryDrag() {
        guard let id = draggingEntry else { return }
        draggingEntry = nil
        if entryOut, let entry = tile.stack.first(where: { $0.id == id }) {
            pendingStack = nil
            moveOut(entry)
            return
        }
        if let order = pendingStack, order.map(\.id) != tile.stack.map(\.id) {
            tile.stack = order
        } else {
            pendingStack = nil
        }
    }

    /// A binding to the launcher at the index in the stack, so its fields write
    /// straight back through the card's tile.
    private func launcherBinding(at index: Int) -> Binding<WidgetTile> {
        Binding(
            get: { tile.stack[index].launcher ?? WidgetTile(kind: .launcher) },
            set: { tile.stack[index] = .launcher($0) }
        )
    }

    private func addLauncher() {
        let launcher = WidgetTile(kind: .launcher)
        tile.stack.append(.launcher(launcher))
        editingEntry = launcher.id
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let path = tile.path { panel.directoryURL = URL(fileURLWithPath: path) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tile.path = url.path
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && url.pathExtension == "app" {
            guard !tile.apps.contains(where: { $0.path == url.path }), let app = DockTile.app(at: url) else { continue }
            tile.stack.append(.app(app))
        }
    }
}

private struct StackEntryFrameReporter: View {
    let id: UUID

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: StackEntryFrameKey.self, value: [id: geometry.frame(in: .named("stack"))])
        }
    }
}

private struct StackEntryFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A launcher's settings: its icon — or one of its own, dropped on the well or
/// chosen — the app, a browser's profile, the arguments as they would be typed
/// after the app on a command line, a name and a badge. On a launcher's own card,
/// and under the row of an app stack for a launcher in it.
private struct LauncherFields: View {
    @Binding var tile: WidgetTile

    /// The profiles of the browser it opens, read when the app changes.
    @State private var browserProfiles: [BrowserProfile] = []
    @State private var iconTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                iconWell
                fields
            }
            Text(launcherHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            if url.pathExtension == "app" {
                tile.setApp(at: url)
                return true
            }
            return false
        }
        .task(id: tile.path) { loadBrowserProfiles() }
    }

    private var fields: some View {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    gridLabel("App")
                    HStack(spacing: 8) {
                        Button(tile.path == nil ? "Choose App…" : "Change…", action: chooseApp)
                            .controlSize(.small)
                        if let name = tile.appName {
                            Text(name)
                                .font(.system(size: 12))
                                .foregroundStyle(launcherAppMissing ? .orange : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                if !browserProfiles.isEmpty {
                    GridRow {
                        gridLabel("Profile")
                        Picker("Profile", selection: browserProfileSelection) {
                            Text("None").tag(String?.none)
                            ForEach(browserProfiles) { profile in
                                Text(profile.name).tag(String?.some(profile.id))
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 220, alignment: .leading)
                    }
                }
                GridRow {
                    gridLabel("Arguments")
                    TextField("Arguments", text: $tile.arguments, prompt: Text("--incognito https://example.com"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 360)
                }
                GridRow {
                    gridLabel("Name")
                    TextField("Name", text: launcherLabel, prompt: Text(tile.appName ?? "Launcher"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 220)
                }
                GridRow {
                    gridLabel("Icon")
                    HStack(spacing: 8) {
                        Button("Choose…", action: chooseIcon)
                            .controlSize(.small)
                        if tile.iconPath != nil {
                            Button("Use App's Icon") { tile.iconPath = nil }
                                .controlSize(.small)
                        }
                        Text("or drop an image or an app on the icon")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if tile.iconPath == nil {
                    GridRow {
                        gridLabel("Badge")
                        HStack(spacing: 8) {
                            TextField("Badge", text: launcherBadge, prompt: Text(badgePrompt))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 44)
                            Text("a letter or two on the icon's corner")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if tile.browserProfile != nil {
                        GridRow {
                            gridLabel("")
                            HStack(spacing: 8) {
                                Toggle("Profile picture", isOn: $tile.showsProfilePicture)
                                    .controlSize(.small)
                                    .disabled(tile.badge != nil)
                                Text(profilePictureNote)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
    }

    /// Whether the browser has a picture saved for the chosen profile — one on a
    /// built-in avatar has none to show, and keeps its initial.
    private var chosenProfileHasPicture: Bool {
        browserProfiles.contains { $0.id == tile.browserProfile?.id && $0.picture != nil }
    }

    private var profilePictureNote: String {
        if tile.badge != nil { return "the badge above takes its place" }
        if !chosenProfileHasPicture { return "the browser has no picture saved for this profile, so its initial stays" }
        return "the account's picture, in place of the initial"
    }

    /// Two characters at most; blank means the profile's own picture or initial.
    private var launcherBadge: Binding<String> {
        Binding(
            get: { tile.badge ?? "" },
            set: { text in
                let trimmed = String(text.prefix(2))
                tile.badge = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var badgePrompt: String {
        guard let profile = tile.browserProfile else { return "" }
        return String(profile.name.prefix(1)).uppercased()
    }

    private func gridLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// The tile as the dock draws it, and a target: an image dropped here becomes
    /// the icon, an app dropped here lends its icon.
    private var iconWell: some View {
        LauncherIconPreview(tile: tile, side: 48)
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(iconTargeted ? 1 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: chooseIcon)
            .help("Click to choose an icon, or drop an image or an app here")
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, Self.canBeIcon(url) else { return false }
                tile.iconPath = url.path
                return true
            } isTargeted: { iconTargeted = $0 }
    }

    private var launcherAppMissing: Bool {
        tile.path.map { !FileManager.default.fileExists(atPath: $0) } ?? false
    }

    private var launcherHint: String {
        if launcherAppMissing { return "The app has moved or been deleted." }
        var hint = "Opens a fresh copy of the app with these arguments — a browser or an editor already running takes them over and opens a window."
        if !browserProfiles.isEmpty { hint = "The profile fills in the browser's own switch; anything more goes in Arguments. " + hint }
        hint += " Quote an argument with spaces; ~/ is your home folder."
        if tile.browserProfile != nil, tile.iconPath == nil {
            hint += " The profile's initial — or its picture, when asked for — is badged on the icon; type a badge of your own to tell two alike apart."
        }
        return hint
    }

    /// An empty name means the app's own.
    private var launcherLabel: Binding<String> {
        Binding(
            get: { tile.label ?? "" },
            set: { tile.label = $0.isEmpty ? nil : $0 }
        )
    }

    /// The chosen profile by id — with its name kept beside it for the tile.
    private var browserProfileSelection: Binding<String?> {
        Binding(
            get: { tile.browserProfile?.id },
            set: { id in
                tile.browserProfile = browserProfiles.first { $0.id == id }.map { BrowserProfileRef(id: $0.id, name: $0.name) }
            }
        )
    }

    private func loadBrowserProfiles() {
        guard let identifier = tile.appURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }), BrowserProfiles.isBrowser(identifier) else {
            browserProfiles = []
            return
        }
        browserProfiles = BrowserProfiles.profiles(of: identifier)
    }

    private static func canBeIcon(_ url: URL) -> Bool {
        if url.pathExtension == "app" { return true }
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .image)
    }

    private func chooseApp() {
        guard let url = LauncherPanels.chooseApp(near: tile.path) else { return }
        tile.setApp(at: url)
    }

    private func chooseIcon() {
        guard let url = LauncherPanels.chooseIcon() else { return }
        tile.iconPath = url.path
    }

}

/// A launcher's icon as its tile will show it, for the well on its card: its own
/// icon, or the app's with the profile's picture on the corner; a placeholder
/// until an app is chosen.
private struct LauncherIconPreview: View {
    let tile: WidgetTile
    let side: CGFloat

    var body: some View {
        if let custom = Launcher.customIcon(of: tile) {
            Image(nsImage: custom).resizable().aspectRatio(contentMode: .fit)
        } else if let app = Launcher.appIcon(of: tile) {
            BadgedIcon(
                image: app,
                badge: Launcher.badgeImage(of: tile, side: BadgedIcon.badgeSide(for: side)),
                side: side,
                ring: Color(nsColor: .windowBackgroundColor)
            )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    Image(systemName: tile.path == nil ? "arrow.up.forward.app" : "questionmark")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                )
        }
    }
}
