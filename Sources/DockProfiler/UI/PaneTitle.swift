import SwiftUI

/// The header the detail panes put in the titlebar: a glyph and whatever the
/// pane wants to name itself. Its height is fixed, and every pane uses it, so
/// the toolbar — and with it the top of the detail pane and its scrollbar —
/// stays put as you move between Settings and a profile.
struct PaneTitle<Content: View>: View {
    static var height: CGFloat { 28 }

    let symbol: String
    var tint: Color = .secondary
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            content()
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
    }
}
