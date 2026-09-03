import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: WelcomeView { [weak self] createdProfile in
                    self?.finish(selecting: createdProfile)
                }
                .environmentObject(ProfileStore.shared)
            )
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.title = ""
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        AppSettings.shared.hasSeenWelcome = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(selecting id: UUID?) {
        window?.close()
        ManagerWindowController.shared.show(selecting: id)
    }
}
