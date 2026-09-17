import AppKit
import SwiftUI

/// The dock's own tooltip. AppKit's help tags do not show reliably over a
/// non-activating panel, and the compact tiles in a column need somewhere to put
/// the detail, so hovering a tile brings up a small slab beside it, on the side
/// away from the dock's edge.
@MainActor
final class DockTooltipController {
    static let shared = DockTooltipController()

    private var panel: NSPanel?
    private var hosting: NSHostingView<DockTooltipView>?
    private var showTask: Task<Void, Never>?

    /// Shows the tip after a short pause, so a pointer just passing through does not
    /// leave a trail of them. `tile` is the tile's frame in its window's SwiftUI
    /// global space, so the tip can centre on the tile rather than the pointer.
    func schedule(title: String, subtitle: String?, edge: DockStripEdge, tile: CGRect) {
        showTask?.cancel()
        showTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self.show(title: title, subtitle: subtitle, edge: edge, tile: tile)
        }
    }

    func cancel() {
        showTask?.cancel()
        showTask = nil
        panel?.orderOut(nil)
    }

    private func show(title: String, subtitle: String?, edge: DockStripEdge, tile: CGRect) {
        makePanelIfNeeded()
        guard let panel, let hosting else { return }
        hosting.rootView = DockTooltipView(title: title, subtitle: subtitle)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        // Centred on the tile along the dock, and just clear of the dock's panel on
        // its far side. The panel is the slab plus the headroom magnified tiles grow
        // into, so the tip stays above a tile at full magnification. Away from the
        // dock's panel — the editor's preview — it sits off the tile instead.
        let mouse = NSEvent.mouseLocation
        let window = NSApp.window(withWindowNumber: NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0))
        let tileOnScreen = window.flatMap { Self.screenRect(for: tile, in: $0) }
        let center = tileOnScreen.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse
        let dock = window.flatMap { CustomDockWindowController.shared.slabFrame(in: $0) != nil ? $0.frame : nil }
        // Beside the dock the tip takes the dock's appearance; beside the editor's
        // preview it keeps the editor's.
        panel.appearance = dock == nil ? nil : CustomDockWindowController.shared.forcedAppearance
        // Off the panel when there is one, off the tile itself otherwise.
        let gap: CGFloat = 10
        let above = dock?.maxY ?? tileOnScreen?.maxY ?? mouse.y + 30
        let below = dock?.minY ?? tileOnScreen?.minY ?? mouse.y - 30
        let right = dock?.maxX ?? tileOnScreen?.maxX ?? mouse.x + 30
        let left = dock?.minX ?? tileOnScreen?.minX ?? mouse.x - 30
        var origin: NSPoint
        switch edge {
        case .bottom: origin = NSPoint(x: center.x - size.width / 2, y: above + gap)
        case .top: origin = NSPoint(x: center.x - size.width / 2, y: below - gap - size.height)
        case .leading: origin = NSPoint(x: right + gap, y: center.y - size.height / 2)
        case .trailing: origin = NSPoint(x: left - gap - size.width, y: center.y - size.height / 2)
        }

        // Keep it on the screen the pointer is on.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// A SwiftUI global-space rect (origin top-left of the window's content) on screen.
    private static func screenRect(for rect: CGRect, in window: NSWindow) -> NSRect? {
        guard let content = window.contentView else { return nil }
        let flipped = NSRect(
            x: rect.minX,
            y: content.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return window.convertToScreen(flipped)
    }

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: DockTooltipView(title: "", subtitle: nil))
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
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        self.hosting = hosting
        self.panel = panel
    }
}

/// A title line and, optionally, a dimmer line under it.
struct DockTooltipView: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DockPalette.onSlab.opacity(0.7))
            }
        }
        .foregroundStyle(DockPalette.onSlab)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 320, alignment: .leading)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DockPalette.slab)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DockPalette.rim, lineWidth: 1)
                )
        )
    }
}

/// The edge the dock lives on, so tips know which way to go.
private struct DockEdgeKey: EnvironmentKey {
    static let defaultValue = DockStripEdge.bottom
}

extension EnvironmentValues {
    var dockEdge: DockStripEdge {
        get { self[DockEdgeKey.self] }
        set { self[DockEdgeKey.self] = newValue }
    }
}

private struct DockTooltipModifier: ViewModifier {
    let title: String
    let subtitle: String?

    @Environment(\.dockEdge) private var edge
    /// Where the tile is, in the window's global space, so the tip can centre on it.
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onHover { inside in
                if inside {
                    DockTooltipController.shared.schedule(title: title, subtitle: subtitle, edge: edge, tile: frame)
                } else {
                    DockTooltipController.shared.cancel()
                }
            }
    }
}

extension View {
    /// Shows the dock's tooltip while the pointer rests on this tile.
    func dockTooltip(_ title: String, _ subtitle: String? = nil) -> some View {
        modifier(DockTooltipModifier(title: title, subtitle: subtitle))
    }
}
