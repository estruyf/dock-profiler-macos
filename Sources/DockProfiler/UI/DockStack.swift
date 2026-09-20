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
        hosting.rootView = DockStackView(content: content, dismiss: { [weak self] in self?.dismiss() })
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        // Centred on the pointer along the dock, and just off the dock's far side —
        // the slab itself when the pointer is in the dock's panel, otherwise whichever
        // of our windows it is in. Failing that, pushed off the pointer far enough to
        // clear a tile.
        let mouse = NSEvent.mouseLocation
        let window = NSApp.window(withWindowNumber: NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0))
        let dock = window.flatMap { CustomDockWindowController.shared.slabFrame(in: $0) ?? $0.frame }
        panel.appearance = window.flatMap { CustomDockWindowController.shared.forcedAppearance(in: $0) }
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
        let hosting = StackHostingView(rootView: DockStackView(content: placeholder, dismiss: {}))
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
    let dismiss: () -> Void

    private let gridColumns = 5
    private let cell = CGSize(width: 84, height: 86)
    private let rowHeight: CGFloat = 40
    private let maxHeight: CGFloat = 360

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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DockPalette.slab)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(DockPalette.rim, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            ForEach(content.items) { item in
                Button {
                    dismiss()
                    item.action()
                } label: {
                    VStack(spacing: 4) {
                        icon(item.icon, size: 44)
                        Text(item.title)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(height: 28, alignment: .top)
                        Circle()
                            .fill(DockPalette.onSlab.opacity(item.isCurrent ? 0.85 : 0))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.top, 6)
                    .frame(width: cell.width, height: cell.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HighlightButtonStyle(cornerRadius: 10))
                .help(item.subtitle ?? item.title)
            }
        }
        .padding(8)
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
