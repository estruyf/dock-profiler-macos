import AppKit
import SwiftUI

/// The widget kinds in the order they are offered, grouped: glanceable things
/// first, then the ones that open into something, then the tools. Shared by the
/// gallery beside the dock and the editor's Add widget menu, so the two agree.
struct WidgetGroup: Identifiable {
    let title: String
    let kinds: [WidgetKind]

    var id: String { title }

    static let all: [WidgetGroup] = [
        WidgetGroup(title: "At a glance", kinds: [.clock, .date, .battery, .accessories, .nowPlaying]),
        WidgetGroup(title: "Files and apps", kinds: [.trash, .airDrop, .folderStack, .appStack, .launcher]),
        WidgetGroup(title: "Your tools", kinds: [.profiles, .agents, .aiUsage]),
        WidgetGroup(title: "Layout", kinds: [.divider]),
    ]
}

/// What the gallery takes from the dock it opened off: the slab, so it is drawn
/// the same way, and the size the dock's widgets are, so the previews are true
/// to what adding one gives you.
struct DockWidgetGalleryStyle {
    var look = DockLook()
    var tint: Color?
    var tileSize: CGFloat = 56
}

/// The gallery, under an id that changes each time it opens, so a search typed
/// into one is not still there the next time.
private struct GalleryRoot: View {
    let token: UUID
    let gallery: DockWidgetGalleryView

    var body: some View { gallery.id(token) }
}

/// A click in the gallery should act at once, without the panel needing to be key.
private final class GalleryHostingView: NSHostingView<GalleryRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The gallery can take key, so its search field can be typed in — but only once
/// the field is clicked, and as a non-activating panel it does that without
/// bringing Dock Profiler forward. Whatever you were working in stays where it was.
private final class GalleryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The widget gallery: a slab that opens off the custom dock — above it, below it
/// or beside it, whichever edge the dock is on — showing every widget as it will
/// look once added. Clicking one adds it to the active profile at once, so the
/// dock behind the gallery fills up as you go.
///
/// Built like `DockStackController`: its own borderless panel, drawn as the dock's
/// slab is, that goes away on a click elsewhere or on Escape.
@MainActor
final class DockWidgetGalleryController {
    static let shared = DockWidgetGalleryController()

    private var panel: GalleryPanel?
    private var hosting: GalleryHostingView?
    private var monitors: [Any] = []

    private init() {}

    var isOpen: Bool { panel?.isVisible == true }

    /// The gap between the slab and the gallery, and between the gallery and the
    /// edges of the screen.
    private static let gap: CGFloat = 8
    private static let margin: CGFloat = 12

    func toggle(near slab: NSRect, on screen: NSScreen, edge: DockStripEdge, style: DockWidgetGalleryStyle, appearance: NSAppearance?) {
        if isOpen {
            dismiss()
        } else {
            show(near: slab, on: screen, edge: edge, style: style, appearance: appearance)
        }
    }

    func show(near slab: NSRect, on screen: NSScreen, edge: DockStripEdge, style: DockWidgetGalleryStyle, appearance: NSAppearance?) {
        DockTooltipController.shared.cancel()
        DockStackController.shared.dismiss()
        makePanelIfNeeded()
        guard let panel, let hosting else { return }

        let visible = screen.visibleFrame
        let height = DockWidgetGalleryView.headerHeight + bodyHeight(beside: slab, in: visible, edge: edge)
        let size = NSSize(width: DockWidgetGalleryView.width, height: height)

        panel.appearance = appearance
        hosting.rootView = GalleryRoot(token: UUID(), gallery: DockWidgetGalleryView(
            style: style,
            bodyHeight: height - DockWidgetGalleryView.headerHeight,
            add: { [weak self] kind in self?.add(kind) },
            dismiss: { [weak self] in self?.dismiss() }
        ))

        let gap = Self.gap
        var origin: NSPoint
        switch edge {
        case .bottom: origin = NSPoint(x: slab.midX - size.width / 2, y: slab.maxY + gap)
        case .top: origin = NSPoint(x: slab.midX - size.width / 2, y: slab.minY - gap - size.height)
        case .leading: origin = NSPoint(x: slab.maxX + gap, y: slab.midY - size.height / 2)
        case .trailing: origin = NSPoint(x: slab.minX - gap - size.width, y: slab.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + Self.margin), max(visible.minX + Self.margin, visible.maxX - size.width - Self.margin))
        origin.y = min(max(origin.y, visible.minY + Self.margin), max(visible.minY + Self.margin, visible.maxY - size.height - Self.margin))

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    func dismiss() {
        guard panel != nil else { return }
        removeMonitors()
        panel?.orderOut(nil)
    }

    /// How tall the list of widgets may be: what the screen leaves between the dock
    /// and its far side, within limits, so the gallery never runs off a small display.
    private func bodyHeight(beside slab: NSRect, in visible: NSRect, edge: DockStripEdge) -> CGFloat {
        let room: CGFloat
        switch edge {
        case .bottom: room = visible.maxY - slab.maxY - Self.gap - Self.margin
        case .top: room = slab.minY - visible.minY - Self.gap - Self.margin
        case .leading, .trailing: room = visible.height - Self.margin * 2
        }
        return min(420, max(190, room - DockWidgetGalleryView.headerHeight))
    }

    // MARK: - Adding

    /// Puts a widget of the kind at the end of the active profile's widgets. A
    /// launcher is nothing without an app, so it asks for one first — and the
    /// gallery steps out of the way while the open panel is up.
    private func add(_ kind: WidgetKind) {
        let store = ProfileStore.shared
        guard var profile = store.activeProfile else { return }
        var widget = WidgetTile(kind: kind)
        if kind == .launcher {
            dismiss()
            NSApp.activate(ignoringOtherApps: true)
            guard let url = LauncherPanels.chooseApp(near: nil) else { return }
            widget.setApp(at: url)
        }
        profile.customDock.widgets.append(widget)
        store.update(profile)
    }

    // MARK: - Dismissal

    /// A click anywhere but in the gallery closes it, as does Escape. Watching the
    /// mouse this way needs no permission, and the events still reach whatever was
    /// clicked.
    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel { self.dismiss() }
            }
            return event
        }) {
            monitors.append(local)
        }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let mine = event.window
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, mine === self.panel else { return false }
                self.dismiss()
                return true
            }
            return handled ? nil : event
        }) {
            monitors.append(escape)
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    // MARK: - Panel

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        let placeholder = DockWidgetGalleryView(style: DockWidgetGalleryStyle(), bodyHeight: 300, add: { _ in }, dismiss: {})
        let hosting = GalleryHostingView(rootView: GalleryRoot(token: UUID(), gallery: placeholder))
        let panel = GalleryPanel(
            contentRect: NSRect(x: 0, y: 0, width: DockWidgetGalleryView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.level = CustomDockWindowController.accessoryLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        // Opening the gallery leaves the front app's focus alone; clicking into the
        // search field is what hands the panel the keyboard.
        panel.becomesKeyOnlyIfNeeded = true
        self.hosting = hosting
        self.panel = panel
    }
}

// MARK: - View

/// The gallery's contents on a slab: a title and a search field, then a card per
/// widget under its group's heading, each showing the widget itself as the dock
/// will draw it.
struct DockWidgetGalleryView: View {
    let style: DockWidgetGalleryStyle
    /// How tall the scrolling list of widgets may be; the controller works it out
    /// from the room the screen leaves beside the dock.
    let bodyHeight: CGFloat
    let add: (WidgetKind) -> Void
    let dismiss: () -> Void

    @ObservedObject private var store = ProfileStore.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var query = ""
    @State private var justAdded: WidgetKind?
    @FocusState private var searchFocused: Bool

    /// Three cards abreast, with a margin each side.
    static let width: CGFloat = 536
    static let headerHeight: CGFloat = 48

    private let columns = 3
    private let cell = CGSize(width: 168, height: 134)
    /// The box a widget is drawn in, shrunk to fit if it is wider than the card.
    private var previewBox: CGSize { CGSize(width: cell.width - 18, height: 62) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DockPalette.rim)
            widgetList(in: bodyHeight)
        }
        .foregroundStyle(DockPalette.onSlab)
        .frame(width: Self.width)
        .background(DockSlab(look: style.look, tint: style.tint, cornerRadius: 16, overContent: true))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, style.look.style.forcedColorScheme ?? systemColorScheme)
        .onExitCommand(perform: dismiss)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Add Widget")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            search
            Button("Done", action: dismiss)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.headerHeight)
    }

    private var search: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(DockPalette.onSlab.opacity(0.5))
            TextField("Search widgets", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DockPalette.onSlab.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 180)
        .background(Capsule().fill(DockPalette.onSlab.opacity(0.09)))
        .overlay(Capsule().strokeBorder(DockPalette.rim, lineWidth: 1))
    }

    // MARK: - The widgets

    @ViewBuilder
    private func widgetList(in height: CGFloat) -> some View {
        let groups = matching
        if groups.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(DockPalette.onSlab.opacity(0.35))
                Text("No widget matches “\(query)”")
                    .font(.system(size: 12))
                    .foregroundStyle(DockPalette.onSlab.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DockPalette.onSlab.opacity(0.45))
                                .padding(.horizontal, 16)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(cell.width), spacing: 0), count: columns),
                                alignment: .leading,
                                spacing: 0
                            ) {
                                ForEach(group.kinds) { kind in
                                    card(kind)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(height: height)
        }
    }

    /// The groups with the kinds the search leaves, groups that lose all of theirs
    /// dropped. An empty search shows everything.
    private var matching: [WidgetGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return WidgetGroup.all }
        return WidgetGroup.all.compactMap { group in
            let kinds = group.kinds.filter {
                $0.title.lowercased().contains(needle) || $0.summary.lowercased().contains(needle)
            }
            return kinds.isEmpty ? nil : WidgetGroup(title: group.title, kinds: kinds)
        }
    }

    // MARK: - Cards

    private func card(_ kind: WidgetKind) -> some View {
        Button {
            add(kind)
            flash(kind)
        } label: {
            VStack(spacing: 0) {
                preview(kind)
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 8)
                Text(kind.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(DockPalette.onSlab.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 26, alignment: .top)
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
            .frame(width: cell.width, height: cell.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(GalleryCardStyle())
        .help("Add \(kind.title) to the dock")
    }

    /// The widget itself, drawn as the dock draws it, shrunk to fit the card. It
    /// takes no clicks of its own: the whole card is the button that adds it.
    private func preview(_ kind: WidgetKind) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DockPalette.onSlab.opacity(0.07))
            FitToBox(box: previewBox) {
                WidgetTileView(tile: WidgetTile(kind: kind))
                    .environment(\.dockTileSize, style.tileSize)
                    .environment(\.dockVertical, false)
                    .environment(\.dockTileCards, style.look.drawsTileCards)
                    .environment(\.dockEdge, .bottom)
            }
            .allowsHitTesting(false)
            if justAdded == kind {
                // Over the widget, not through it: a ring gauge or a track name
                // showing behind the word left it hard to read.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DockPalette.solid)
                    .overlay(
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DockPalette.onSlab)
                    )
                    .transition(.opacity)
            }
        }
        .frame(width: previewBox.width, height: previewBox.height)
        .animation(.easeOut(duration: 0.12), value: justAdded == kind)
        .overlay(alignment: .topTrailing) { countChip(for: kind) }
    }

    /// How many of this kind the profile already has, on the corner of the preview.
    @ViewBuilder
    private func countChip(for kind: WidgetKind) -> some View {
        let count = widgets.filter { $0.kind == kind }.count
        if count > 0 {
            Group {
                if count == 1 {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                } else {
                    Text("\(count)").font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(DockPalette.onSlab.opacity(0.85))
            .frame(width: 16, height: 16)
            .background(Circle().fill(DockPalette.onSlab.opacity(0.16)))
            .padding(5)
            .help(count == 1 ? "Already in the dock" : "\(count) in the dock")
        }
    }

    private var widgets: [WidgetTile] { store.activeProfile?.customDock.widgets ?? [] }

    /// A tick on the card that was just clicked, so a widget added to a dock that
    /// is out of sight — hidden, or on another display — still says it landed.
    private func flash(_ kind: WidgetKind) {
        justAdded = kind
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if justAdded == kind { justAdded = nil }
        }
    }
}

/// A gallery card that lights up under the pointer and dims while pressed.
private struct GalleryCardStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DockPalette.onSlab.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.07 : 0)))
            )
            .onHover { hovering = $0 }
    }
}

// MARK: - Fitting

private struct NaturalSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// A view laid out at its natural size and shrunk, if need be, to fit inside a
/// box. The size is measured behind the content, which `scaleEffect` does not
/// change — it is drawn after layout — so the two cannot chase each other.
private struct FitToBox<Content: View>: View {
    let box: CGSize
    @ViewBuilder let content: () -> Content

    @State private var natural: CGSize = .zero

    private var scale: CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 1 }
        return min(1, min(box.width / natural.width, box.height / natural.height))
    }

    var body: some View {
        content()
            .fixedSize()
            .background(GeometryReader { geometry in
                Color.clear.preference(key: NaturalSizeKey.self, value: geometry.size)
            })
            .onPreferenceChange(NaturalSizeKey.self) { natural = $0 }
            .scaleEffect(scale)
            .frame(width: box.width, height: box.height)
            .clipped()
    }
}
