import AppKit
import Combine
import SwiftUI

/// Borderless panel that can take the keyboard without the app owning a real window.
private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SwitcherWindowController: NSObject, NSWindowDelegate {
    static let shared = SwitcherWindowController()

    private var panel: SwitcherPanel?
    private var hosting: NSHostingView<AnyView>?
    private let model = SwitcherModel()
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        makePanelIfNeeded()
        guard let panel else { return }

        model.reset()
        resizeToFit()
        position(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Panel

    private func makePanelIfNeeded() {
        guard panel == nil else { return }

        let root = AnyView(
            SwitcherView(model: model) { [weak self] profile in
                self?.activate(profile)
            }
            .environmentObject(ProfileStore.shared)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = SwitcherPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        self.hosting = hosting
        self.panel = panel

        // Keep the panel snug around the filtered list while typing.
        model.$query
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.resizeToFit() }
            }
            .store(in: &cancellables)
    }

    private func resizeToFit() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frame
        // Grow downwards: the search field should not move under the caret.
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - visible.height * 0.20
        )
        panel.setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Pull the plain values out of the event so nothing non-Sendable crosses over.
            let keyCode = event.keyCode
            let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            let characters = event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, rawFlags: rawFlags, characters: characters) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(keyCode: UInt16, rawFlags: UInt, characters: String?) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)

        if flags.contains(.command), let digit = Int(characters ?? ""), (1...9).contains(digit) {
            model.select(digit - 1)
            if let profile = model.selectedProfile { activate(profile) }
            return true
        }

        switch Int(keyCode) {
        case 53:  // esc
            hide()
            return true
        case 125:  // down
            model.moveSelection(by: 1)
            return true
        case 126:  // up
            model.moveSelection(by: -1)
            return true
        case 48:  // tab
            model.moveSelection(by: flags.contains(.shift) ? -1 : 1)
            return true
        case 36, 76:  // return / enter
            if let profile = model.selectedProfile { activate(profile) }
            return true
        default:
            return false
        }
    }

    private func activate(_ profile: DockProfile) {
        hide()
        ProfileStore.shared.activate(profile.id)
    }
}
