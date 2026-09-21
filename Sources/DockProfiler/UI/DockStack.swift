import AppKit
import SwiftUI

/// One entry in an open stack: a file, an app, a session or a profile.
struct DockStackItem: Identifiable {
    enum Icon {
        case image(NSImage)
        case symbol(String, Color)
        case dot(Color)
        /// A ring filled to the fraction, for what is left of an allowance.
        case ring(Double, Color)
    }

    var id: String
    var title: String
    var subtitle: String?
    var icon: Icon
    /// Ticked in a list; underlined with a running dot in a grid.
    var isCurrent = false
    var action: () -> Void
    /// The item's context menu; none without any.
    var menu: [DockStackMenuEntry] = []
}

/// One line of an item's context menu in a stack.
enum DockStackMenuEntry {
    case item(String, destructive: Bool = false, action: () -> Void)
    case separator
}

/// How a stack lays its items out: files and apps as a grid of icons, sessions and
/// profiles as a list with a line of detail each.
enum DockStackStyle {
    case grid
    case list
}

struct DockStackContent {
    var title: String
    var items: [DockStackItem]
    var style: DockStackStyle
    /// What the stack says when it has nothing in it.
    var emptyText: String
    /// An action under the items, like the Dock's "Open in Finder".
    var footer: DockStackItem?
    /// For a stack whose order is its own to set: the items can be held and
    /// dragged along the grid, and letting go hands back the ids in their new order.
    var onReorder: (([String]) -> Void)?
    /// With `onReorder`: an item carried off the panel and let go leaves the stack.
    var onMoveOut: ((String) -> Void)?
}

/// A click on the stack should act at once, without the panel needing to be key.
private final class StackHostingView: NSHostingView<DockStackView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel a stack widget opens into: a slab beside the dock, on the side away
/// from its edge, that goes away on a click anywhere else. Like the tooltip, it is
/// its own non-activating panel so the dock never takes focus from the front app.
@MainActor
final class DockStackController {
    static let shared = DockStackController()

    private var panel: NSPanel?
    private var hosting: StackHostingView?
    private var monitors: [Any] = []
    /// The widget whose stack is open, so a second click on it closes the stack.
    private(set) var openID: UUID?

    private init() {}

    var isOpen: Bool { panel?.isVisible == true }

    /// Opens the stack for a widget, or closes it if it is the one already open.
    func toggle(for id: UUID, content: DockStackContent, edge: DockStripEdge) {
        if openID == id, isOpen {
            dismiss()
        } else {
            show(for: id, content: content, edge: edge)
        }
    }

    func show(for id: UUID, content: DockStackContent, edge: DockStripEdge) {
        DockTooltipController.shared.cancel()
        makePanelIfNeeded()
        guard let panel, let hosting else { return }
        openID = id

        // Centred on the pointer along the dock, and just off the dock's far side —
        // the slab itself when the pointer is in the dock's panel, otherwise whichever
        // of our windows it is in. Failing that, pushed off the pointer far enough to
        // clear a tile.
        let mouse = NSEvent.mouseLocation
        let window = NSApp.window(withWindowNumber: NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0))
        let dock = window.flatMap { CustomDockWindowController.shared.slabFrame(in: $0) ?? $0.frame }
        panel.appearance = window.flatMap { CustomDockWindowController.shared.forcedAppearance(in: $0) }
        // Drawn as the dock's own slab is, so the stack belongs to it.
        let slab = window.flatMap { CustomDockWindowController.shared.slabLook(in: $0) }
        hosting.rootView = DockStackView(content: content, look: slab?.look ?? DockLook(), tint: slab?.tint, dismiss: { [weak self] in self?.dismiss() })
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let gap: CGFloat = 5
        let reach: CGFloat = 48
        var origin: NSPoint
        switch edge {
        case .bottom:
            origin = NSPoint(x: mouse.x - size.width / 2, y: dock.map { $0.maxY + gap } ?? mouse.y + reach)
        case .top:
            origin = NSPoint(x: mouse.x - size.width / 2, y: (dock.map { $0.minY - gap } ?? mouse.y - reach) - size.height)
        case .leading:
            origin = NSPoint(x: dock.map { $0.maxX + gap } ?? mouse.x + reach, y: mouse.y - size.height / 2)
        case .trailing:
            origin = NSPoint(x: (dock.map { $0.minX - gap } ?? mouse.x - reach) - size.width, y: mouse.y - size.height / 2)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    func dismiss() {
        removeMonitors()
        openID = nil
        panel?.orderOut(nil)
    }

    // MARK: - Dismissal

    /// A click anywhere but on the stack closes it. Watching the mouse this way
    /// needs no permission, and the events still reach whatever was clicked.
    private func installMonitors() {
        removeMonitors()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel { self.dismiss() }
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    // MARK: - Panel

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        let placeholder = DockStackContent(title: "", items: [], style: .list, emptyText: "")
        let hosting = StackHostingView(rootView: DockStackView(content: placeholder, look: DockLook(), tint: nil, dismiss: {}))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
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
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        self.hosting = hosting
        self.panel = panel
    }
}

// MARK: - View

/// The stack's contents on a slab: a title, the items as a grid or a list, and an
/// optional action underneath. Sized to its content, up to a few rows, then scrolls.
struct DockStackView: View {
    let content: DockStackContent
    /// The dock's slab, so the stack is drawn as the dock is.
    let look: DockLook
    let tint: Color?
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var systemColorScheme

    private let gridColumns = 5
    private let cell = CGSize(width: 84, height: 90)
    private let rowHeight: CGFloat = 40
    private let maxHeight: CGFloat = 360

    /// A held item, carried along the grid — or off the panel, to leave the stack.
    @State private var dragging: String?
    @State private var dragPoint: CGPoint = .zero
    @State private var pendingOrder: [DockStackItem]?
    @State private var frames: [String: CGRect] = [:]
    @State private var gridSize: CGSize = .zero
    /// The grid's frame in the hosting view, to place mouse events from `dragMonitor`.
    @State private var gridInHost: CGRect = .zero
    @State private var dragMonitor: Any?
    @State private var out = false

    private var items: [DockStackItem] { pendingOrder ?? content.items }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if content.items.isEmpty {
                Text(content.emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            } else {
                ScrollView(.vertical, showsIndicators: content.items.count > visibleCapacity) {
                    switch content.style {
                    case .grid: grid
                    case .list: list
                    }
                }
                .frame(height: scrollHeight)
            }

            if let footer = content.footer {
                Divider().overlay(DockPalette.rim)
                Button {
                    dismiss()
                    footer.action()
                } label: {
                    Label(footer.title, systemImage: symbolName(for: footer.icon) ?? "arrow.up.forward.square")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HighlightButtonStyle(cornerRadius: 0))
            }
        }
        .foregroundStyle(DockPalette.onSlab)
        .frame(width: width)
        .background(DockSlab(look: look, tint: tint, cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, look.style.forcedColorScheme ?? systemColorScheme)
    }

    private var columns: Int { min(gridColumns, max(1, content.items.count)) }

    private var width: CGFloat {
        switch content.style {
        case .grid: return content.items.isEmpty ? 220 : CGFloat(columns) * cell.width + 16
        case .list: return 260
        }
    }

    /// Rows that fit before the stack starts to scroll.
    private var visibleCapacity: Int {
        switch content.style {
        case .grid: return Int(maxHeight / cell.height) * columns
        case .list: return Int(maxHeight / rowHeight)
        }
    }

    private var scrollHeight: CGFloat {
        switch content.style {
        case .grid:
            let rows = Int((Double(content.items.count) / Double(columns)).rounded(.up))
            return min(maxHeight, CGFloat(rows) * cell.height + 8)
        case .list:
            return min(maxHeight, CGFloat(content.items.count) * rowHeight + 8)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell.width), spacing: 0), count: columns), spacing: 0) {
            ForEach(items) { item in
                gridCell(item)
                    .background(StackCellFrameReporter(id: item.id))
                    // While held, the slot stays in the grid — invisible, shuffling
                    // with the others — and the item is drawn as the ghost.
                    .opacity(dragging == item.id ? 0 : 1)
                    .allowsHitTesting(dragging != item.id)
                    .simultaneousGesture(dragGesture(item), including: content.onReorder == nil ? .subviews : .all)
            }
        }
        .padding(8)
        .coordinateSpace(name: "stack")
        .onPreferenceChange(StackCellFrameKey.self) { frames = $0 }
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { gridSize = geometry.size; gridInHost = geometry.frame(in: .global) }
                .onChange(of: geometry.size) { _, size in gridSize = size; gridInHost = geometry.frame(in: .global) }
        })
        .overlay(ghost)
    }

    private func gridCell(_ item: DockStackItem) -> some View {
        Button {
            dismiss()
            item.action()
        } label: {
            VStack(spacing: 0) {
                icon(item.icon, size: 44)
                // The running dot sits right under the icon, as under a dock tile.
                Circle()
                    .fill(DockPalette.onSlab.opacity(item.isCurrent ? 0.85 : 0))
                    .frame(width: 4, height: 4)
                    .frame(height: 8)
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.top, 6)
            .frame(width: cell.width, height: cell.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightButtonStyle(cornerRadius: 10))
        .help(item.subtitle ?? item.title)
        .contextMenu { menu(for: item) }
    }

    @ViewBuilder
    private func menu(for item: DockStackItem) -> some View {
        ForEach(Array(item.menu.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .item(let title, let destructive, let action):
                Button(title, role: destructive ? .destructive : nil) {
                    dismiss()
                    action()
                }
            case .separator:
                Divider()
            }
        }
    }

    // MARK: - Dragging

    /// The held item, lifted and following the pointer — kept within the panel,
    /// with a word on what letting go does once the pointer has left it.
    @ViewBuilder
    private var ghost: some View {
        if dragging != nil, let item = items.first(where: { $0.id == dragging }) {
            let x = min(max(dragPoint.x, cell.width / 2), max(cell.width / 2, gridSize.width - cell.width / 2))
            let y = min(max(dragPoint.y, cell.height / 2), max(cell.height / 2, gridSize.height - cell.height / 2))
            VStack(spacing: 0) {
                icon(item.icon, size: 44)
                Color.clear.frame(height: 8)
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.top, 6)
            .frame(width: cell.width, height: cell.height)
            .scaleEffect(out ? 0.9 : 1.08)
            .opacity(out ? 0.55 : 1)
            .overlay {
                if out {
                    Text("Out of stack")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.75)))
                        .fixedSize()
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .animation(.easeOut(duration: 0.12), value: out)
            .position(x: x, y: y)
            .allowsHitTesting(false)
        }
    }

    /// Hold an item for a moment, then move it — the dock's own gesture.
    private func dragGesture(_ item: DockStackItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("stack")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging != item.id { beginDrag(item) }
                guard let drag else { return }
                dragMoved(to: drag.location)
            }
            .onEnded { _ in endDrag() }
    }

    private func beginDrag(_ item: DockStackItem) {
        dragging = item.id
        pendingOrder = content.items
        out = false
        dragPoint = frames[item.id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
        installDragMonitor()
    }

    /// The pointer has moved to `point`, in the grid's space. Off the panel by a
    /// margin, the drag becomes a move out; over the grid, the others shuffle aside.
    private func dragMoved(to point: CGPoint) {
        guard let id = dragging, let held = items.first(where: { $0.id == id }) else { return }
        dragPoint = point
        let margin: CGFloat = 24
        out = content.onMoveOut != nil
            && (point.x < -margin || point.y < -margin || point.x > gridSize.width + margin || point.y > gridSize.height + margin)
        var order = items.filter { $0.id != id }
        if !out {
            // The cell the pointer is in, reading order: rows first, then along the row.
            let target = order.filter { other in
                guard let frame = frames[other.id] else { return false }
                if abs(frame.midY - point.y) <= cell.height / 2 { return frame.midX < point.x }
                return frame.midY < point.y
            }.count
            order.insert(held, at: target)
        }
        guard order.map(\.id) != items.map(\.id) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { pendingOrder = order }
    }

    /// AppKit keeps sending the drag to the window the mouse went down in, wherever
    /// the pointer goes; SwiftUI's gesture only reports it inside the window. Once a
    /// drag has begun the events are read directly, in the hosting view's (flipped)
    /// space, and placed against the grid's frame in it.
    private func installDragMonitor() {
        removeDragMonitor()
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                guard let host = event.window?.contentView else { return }
                let inHost = host.convert(event.locationInWindow, from: nil)
                let point = CGPoint(x: inHost.x - gridInHost.minX, y: inHost.y - gridInHost.minY)
                dragMoved(to: point)
                if event.type == .leftMouseUp { endDrag() }
            }
            return event
        }
    }

    private func removeDragMonitor() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
    }

    private func endDrag() {
        guard let id = dragging else { return }
        dragging = nil
        removeDragMonitor()
        if out {
            out = false
            pendingOrder = nil
            dismiss()
            content.onMoveOut?(id)
            return
        }
        if let order = pendingOrder, order.map(\.id) != content.items.map(\.id) {
            content.onReorder?(order.map(\.id))
        } else {
            pendingOrder = nil
        }
    }

    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(content.items) { item in
                Button {
                    dismiss()
                    item.action()
                } label: {
                    HStack(spacing: 10) {
                        icon(item.icon, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if item.isCurrent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HighlightButtonStyle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func icon(_ icon: DockStackItem.Icon, size: CGFloat) -> some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        case .symbol(let name, let color):
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(color.opacity(0.18))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: name)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(color)
                )
        case .dot(let color):
            Circle()
                .fill(color)
                .frame(width: size * 0.45, height: size * 0.45)
                .frame(width: size, height: size)
        case .ring(let fraction, let color):
            LevelRing(fraction: fraction, color: color, lineWidth: size * 0.14)
                .frame(width: size * 0.8, height: size * 0.8)
                .frame(width: size, height: size)
        }
    }

    private func symbolName(for icon: DockStackItem.Icon) -> String? {
        if case .symbol(let name, _) = icon { return name }
        return nil
    }
}

private struct StackCellFrameReporter: View {
    let id: String

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: StackCellFrameKey.self, value: [id: geometry.frame(in: .named("stack"))])
        }
    }
}

private struct StackCellFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A row or cell that lights up under the pointer and dims while pressed.
private struct HighlightButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DockPalette.onSlab.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.09 : 0)))
            )
            .onHover { hovering = $0 }
    }
}
