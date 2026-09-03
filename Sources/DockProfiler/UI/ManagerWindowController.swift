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
            // The toolbar names the profile; a second title beside it just repeats.
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = false
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
}
