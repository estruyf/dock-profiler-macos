import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Dock, drawn as a Dock. Reordering a profile happens here rather than in a list.
struct DockPreviewStrip: View {
    @Binding var tiles: [DockTile]
    @Binding var selection: UUID?
    let onAdd: () -> Void
    let onDropURLs: ([URL]) -> Void

    @State private var dragging: DockTile?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tiles) { tile in
                    tileView(tile)
                        .onDrag {
                            dragging = tile
                            return NSItemProvider(object: tile.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: TileReorderDelegate(item: tile, tiles: $tiles, dragging: $dragging)
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
            .onDrop(of: [.text], delegate: DragEndDelegate(dragging: $dragging))
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
        .dropDestination(for: URL.self) { urls, _ in
            onDropURLs(urls)
            return true
        }
    }

    @ViewBuilder
    private func tileView(_ tile: DockTile) -> some View {
        let isSelected = selection == tile.id

        // A plain view rather than a Button: a Button swallows the mouse-down that
        // `onDrag` needs to start a drag session.
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
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .opacity(isSelected ? 1 : 0)
                .padding(-3)
        )
        .overlay(alignment: .topTrailing) {
            if tile.isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(2)
            }
        }
        // The spacer is only an outline; without this, clicks inside it fall through.
        .contentShape(Rectangle())
        .onTapGesture { selection = tile.id }
        .opacity(dragging?.id == tile.id ? 0.35 : 1)
        .help(tile.label)
        .contextMenu {
            Button("Remove from profile", role: .destructive) {
                tiles.removeAll { $0.id == tile.id }
                if selection == tile.id { selection = nil }
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

/// Live reordering: the tiles shuffle as the drag passes over them.
private struct TileReorderDelegate: DropDelegate {
    let item: DockTile
    @Binding var tiles: [DockTile]
    @Binding var dragging: DockTile?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id,
              let from = tiles.firstIndex(where: { $0.id == dragging.id }),
              let to = tiles.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            tiles.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Catches a tile dropped on the strip itself (between tiles or in the padding) so the
/// dragged tile is not left dimmed.
private struct DragEndDelegate: DropDelegate {
    @Binding var dragging: DockTile?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragging == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
