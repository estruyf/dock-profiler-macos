import AppKit
import SwiftUI

/// The custom-dock half of a profile: what it shows, where it sits, and its widgets.
struct CustomDockOptionsView: View {
    @Binding var options: CustomDockOptions

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
                section("Size") { sizeSection }
                widgetsSection
            }
            .disabled(!options.enabled)
            .opacity(options.enabled ? 1 : 0.45)
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
        }
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
                        Label(kind.title, systemImage: kind.symbolName)
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
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
            Text("A clock, the Trash, a folder, a stack of apps, what is playing, your profiles or your coding agents.")
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
        [.trash, .folderStack, .appStack],
        [.profiles, .agents],
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
                    .overlay(
                        Image(systemName: tile.kind.symbolName)
                            .font(.system(size: 13))
                    )
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
        default:
            EmptyView()
        }
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
