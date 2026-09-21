import AppKit
import SwiftUI

/// The profile manager lives in a plain `NSWindow` so it can be opened from the
/// menu bar, from a re-open of the app, or from anywhere else in the process.
@MainActor
final class ManagerWindowController: NSObject, NSWindowDelegate {
    static let shared = ManagerWindowController()

    private var window: NSWindow?

    func show(selecting id: UUID? = nil) {
        if let id { WindowRouter.shared.pendingSelection = id }

        if window == nil {
            let hosting = NSHostingController(
                rootView: ProfilesWindow().environmentObject(ProfileStore.shared)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Dock Profiles"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // Both after the style mask, which is what AppKit reads them against.
            // The toolbar names the profile; a second title beside it just repeats
            // — and left to decide for itself, AppKit can give the title a row of
            // its own and rule a line across the toolbar underneath it.
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = false
            // Without this AppKit rules a hairline across the titlebar at the
            // height a title row would have had — straight through the toolbar
            // that names the profile.
            window.titlebarSeparatorStyle = .none
            window.setContentSize(NSSize(width: 940, height: 620))
            window.setFrameAutosaveName("DockProfilerManagerWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The pre-macOS 15 half of hiding the title (see `NoWindowTitle`): SwiftUI
    /// can set it visible again when the detail pane changes, and this puts it
    /// back on the next window update. `.navigationTitle("")` would do it too,
    /// but it takes the pane's own toolbar items with it.
    func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.titleVisibility != .hidden else { return }
        window.titleVisibility = .hidden
    }

    /// Settings is a row in the manager's sidebar rather than a window of its
    /// own, so opening it means opening the manager on that row.
    func showSettings() {
        WindowRouter.shared.settingsRequest += 1
        show()
    }

    /// The custom dock's settings are the Custom Dock tab of the profile that
    /// shows it, so a right-click on the dock opens the editor there.
    func showCustomDock(of id: UUID, widgets: Bool = false) {
        WindowRouter.shared.pendingWidgets = widgets
        WindowRouter.shared.pendingCustomDock = id
        show(selecting: id)
    }
}
