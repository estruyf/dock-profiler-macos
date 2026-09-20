import AppKit
import SwiftUI

/// The custom-dock half of a profile: what it shows, where it sits, and its widgets.
struct CustomDockOptionsView: View {
    @Binding var options: CustomDockOptions
    /// The profile's colour, for the tinted look and its preview.
    var tint: Color = .blue

    @ObservedObject private var accessibility = AccessibilityDisplay.shared
    /// The displays connected right now, for the per-display positions.
    @State private var screens = NSScreen.screens

    /// Width of the label column, so pickers and sliders line up down the form.
    private let labelWidth: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show a custom dock when this profile is activated", isOn: $options.enabled)
                Text("The macOS Dock has no room for widgets, so Dock Profiler draws a dock of its own. It follows whichever profile is active and never takes focus from what you are doing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                section("Layout") { layoutSection }
                section("Position") { positionSection }
                section("Style") { styleSection }
                section("Size") { sizeSection }
                widgetsSection
            }
            .disabled(!options.enabled)
            .opacity(options.enabled ? 1 : 0.45)
        }
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
            indented {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Hide until the pointer reaches its edge", isOn: $options.autohide)
                    if options.autohide {
                        Toggle("Leave a mark on the edge while it is hidden", isOn: $options.edgeHint)
                            .padding(.leading, 20)
                    }
                }
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
        }
    }

    // MARK: - Widgets

    private var widgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
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
                        ? "Drag the tiles in the preview to reorder them"
                        : "Arrange them among your apps in the preview above")
                }
                addWidgetMenu("Add widget")
            }

            if options.widgets.isEmpty {
                emptyState
            } else if options.mode == .detached {
                previewAndCards
            } else {
                cards
            }
        }
    }

    private func addWidgetMenu(_ title: String) -> some View {
        Menu(title) {
            ForEach(Self.widgetGroups, id: \.self) { group in
                ForEach(group) { kind in
                    Button {
                        options.widgets.append(WidgetTile(kind: kind))
                    } label: {
                        if let image = WidgetKindIcon.menuImage(for: kind) {
                            Label { Text(kind.title) } icon: { Image(nsImage: image) }
                        } else {
                            Label(kind.title, systemImage: kind.symbolName)
                        }
                    }
                }
                if group != Self.widgetGroups.last { Divider() }
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

    private var cards: some View {
        // One card per line: two abreast left the settings on the wide cards cramped.
        LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(Array(options.widgets.enumerated()), id: \.element.id) { index, tile in
                WidgetSettingsCard(tile: binding(for: tile.id)) {
                    options.widgets.removeAll { $0.id == tile.id }
                }
                .contextMenu {
                    // In a combined dock the order lives in the preview above.
                    if options.mode == .detached {
                        Button("Move up") { move(index, by: -1) }
                            .disabled(index == 0)
                        Button("Move down") { move(index, by: 1) }
                            .disabled(index == options.widgets.count - 1)
                        Divider()
                    }
                    Button("Remove from profile", role: .destructive) {
                        options.widgets.removeAll { $0.id == tile.id }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(options.mode == .combined ? "No widgets among your apps yet" : "No widgets yet")
                .font(.system(size: 13, weight: .medium))
            Text("A clock, the Trash, AirDrop, a folder, a stack of apps, what is playing, your profiles, your coding agents or your AI usage.")
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

    /// Glanceable things first, then the ones that open into something.
    private static let widgetGroups: [[WidgetKind]] = [
        [.clock, .date, .battery, .nowPlaying],
        [.trash, .airDrop, .folderStack, .appStack],
        [.profiles, .agents, .aiUsage],
    ]

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
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
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

private struct WidgetSettingsCard: View {
    @Binding var tile: WidgetTile
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("Remove from profile")
            }
            if tile.kind.isConfigurable {
                settings
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .onHover { hovering = $0 }
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
        case .agents:
            Toggle("One tile that opens into the sessions", isOn: $tile.stacked)
                .controlSize(.small)
        case .nowPlaying:
            Toggle("Show previous and next buttons", isOn: $tile.showsControls)
                .controlSize(.small)
        case .aiUsage:
            usageSettings
        default:
            EmptyView()
        }
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

    /// The apps in the stack as a row of icons — right-click one to take it out —
    /// with a button to add more. Apps dropped from Finder land here too.
    private var appList: some View {
        HStack(spacing: 6) {
            ForEach(tile.apps) { app in
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                .help(app.label)
                .contextMenu {
                    Button("Remove \(app.label)", role: .destructive) {
                        tile.apps.removeAll { $0.id == app.id }
                    }
                }
            }
            Button(tile.apps.isEmpty ? "Add Apps…" : "Add…", action: chooseApps)
                .controlSize(.small)
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        }
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
            tile.apps.append(app)
        }
    }
}
