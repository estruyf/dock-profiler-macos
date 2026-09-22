import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Dock, drawn as a Dock. Reordering a profile happens here rather than in a list.
/// With a combined custom dock the row carries the widgets too, in among the apps.
struct DockPreviewStrip: View {
    @Binding var items: [DockStripItem]
    @Binding var selection: UUID?
    let onAdd: () -> Void
    /// Files dropped from Finder, and the item they landed on — nil for the end of the row.
    let onDropURLs: ([URL], UUID?) -> Void

    @State private var dragging: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    itemView(item)
                        .onDrag {
                            dragging = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text, .fileURL],
                            delegate: DockRowReorderDelegate(
                                id: item.id, items: $items, dragging: $dragging,
                                onDropURLs: { urls in onDropURLs(urls, item.id) }
                            )
                        )
                }

                Button(action: onAdd) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            DockPalette.onSlab.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(DockPalette.onSlab.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .help("Add an app to this profile")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // A tile let go in the gaps between tiles still ends the drag cleanly.
            .onDrop(of: [.text], delegate: DockRowDragEndDelegate(dragging: $dragging))
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DockPalette.slab)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(DockPalette.rim, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 7, y: 2)
        )
        // Anywhere else on the strip — after the last tile, or the empty end — adds to the end.
        .dropDestination(for: URL.self) { urls, _ in
            onDropURLs(urls, nil)
            return true
        }
    }

    @ViewBuilder
    private func itemView(_ item: DockStripItem) -> some View {
        let isSelected = selection == item.id

        // A plain view rather than a Button: a Button swallows the mouse-down that
        // `onDrag` needs to start a drag session.
        Group {
            switch item {
            case .widget(let widget):
                WidgetTileView(tile: widget)
                    // Widgets are live, and a click here should select, not act.
                    .allowsHitTesting(false)
            case .tile(let tile):
                tileView(tile)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .opacity(isSelected ? 1 : 0)
                .padding(-3)
        )
        .overlay(alignment: .topTrailing) {
            if let tile = item.tile, tile.isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(2)
            }
        }
        // The spacer is only an outline; without this, clicks inside it fall through.
        .contentShape(Rectangle())
        .onTapGesture { selection = item.id }
        .opacity(dragging == item.id ? 0.35 : 1)
        .help(item.tile?.label ?? item.widget?.title ?? "")
        .contextMenu {
            Button("Remove from profile", role: .destructive) {
                items.removeAll { $0.id == item.id }
                if selection == item.id { selection = nil }
            }
        }
    }

    @ViewBuilder
    private func tileView(_ tile: DockTile) -> some View {
        Group {
            if tile.kind.isSpacer {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        DockPalette.onSlab.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .frame(width: 18, height: 56)
            } else if let icon = tile.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DockPalette.onSlab.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: tile.isMissing ? "questionmark" : tile.kind.symbolName)
                            .foregroundStyle(DockPalette.onSlab.opacity(0.7))
                    )
            }
        }
    }
}

/// The real Dock is a translucent slab that follows the system appearance: dark grey
/// in Dark Mode, light grey in Light Mode, with a hairline rim. Match it in both, or
/// the preview ends up inverted.
enum DockPalette {
    static let slab = dynamic(
        // Slightly lighter than the window in Dark Mode so the slab still reads as a
        // separate panel — the real Dock gets that separation from the wallpaper.
        dark: NSColor(calibratedWhite: 0.21, alpha: 0.95),
        light: NSColor(calibratedWhite: 0.82, alpha: 0.95)
    )

    /// The slab with no blur behind it: for Reduce transparency, or by choice.
    static let solid = dynamic(
        dark: NSColor(calibratedWhite: 0.19, alpha: 1),
        light: NSColor(calibratedWhite: 0.88, alpha: 1)
    )

    /// The dimming layer over clear Liquid Glass: towards the slab's own shade,
    /// enough that the tiles read over whatever is behind, still seen through.
    static let glassDim = dynamic(
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.5),
        light: NSColor(calibratedWhite: 1.0, alpha: 0.5)
    )

    /// The dimming layer under a slab that floats over other apps' windows rather
    /// than the desktop — a tip or a stack. A blur takes its shade from whatever is
    /// behind it, so over a white window it comes out near white while the text
    /// stays light: this holds the slab near its own shade whatever is behind.
    static let contentDim = dynamic(
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.62),
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62)
    )

    static let rim = dynamic(
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16),
        light: NSColor(calibratedWhite: 0.0, alpha: 0.12)
    )

    /// Foreground that reads on the slab, whichever way round it is.
    static let onSlab = dynamic(
        dark: NSColor(calibratedWhite: 1.0, alpha: 1.0),
        light: NSColor(calibratedWhite: 0.0, alpha: 1.0)
    )

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Live reordering: the items shuffle as the drag passes over them. A drag from
/// Finder is not a reorder; it is handed to `onDropURLs` to land on this item.
/// Shared by the Dock preview and the Items list, which edit the same row.
struct DockRowReorderDelegate: DropDelegate {
    let id: UUID
    @Binding var items: [DockStripItem]
    @Binding var dragging: UUID?
    var onDropURLs: (([URL]) -> Void)?

    private var isReordering: Bool { dragging != nil }

    func validateDrop(info: DropInfo) -> Bool {
        if isReordering { return true }
        return onDropURLs != nil && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != id,
              let from = items.firstIndex(where: { $0.id == dragging }),
              let to = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isReordering ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if isReordering {
            dragging = nil
            return true
        }
        guard let onDropURLs else { return false }
        loadFileURLs(from: info, completion: onDropURLs)
        return true
    }
}

/// Catches an item dropped on the container itself (between items or in the padding)
/// so the dragged one is not left dimmed. Anything else falls through to the container.
struct DockRowDragEndDelegate: DropDelegate {
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragging == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Reads the file URLs out of a drop, in the order they were dragged, and hands them
/// over on the main queue.
private func loadFileURLs(from info: DropInfo, completion: @escaping ([URL]) -> Void) {
    let providers = info.itemProviders(for: [.fileURL])
    guard !providers.isEmpty else { return }
    var urls = [URL?](repeating: nil, count: providers.count)
    let group = DispatchGroup()
    let lock = NSLock()
    for (index, provider) in providers.enumerated() {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            lock.lock()
            urls[index] = url
            lock.unlock()
            group.leave()
        }
    }
    group.notify(queue: .main) {
        completion(urls.compactMap { $0 })
    }
}

