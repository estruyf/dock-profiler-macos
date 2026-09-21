import AppKit
import ApplicationServices

/// One open window of another app, for the custom dock's tile menus: the Dock
/// lists an app's windows in its tile's menu and brings the chosen one forward,
/// and so does this. Another app's windows are only reachable through
/// Accessibility, the permission the badges already use; without it there is
/// no list.
@MainActor
struct AppWindow: Identifiable {
    let id: Int
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    let isMinimized: Bool
    /// The window the app would show first — the Dock's check mark.
    let isFocused: Bool

    /// Brings the window forward and the app with it, as choosing it in the
    /// Dock's menu does; a minimized window comes back off the Dock.
    func raise() {
        if isMinimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AppWindows.activate(app)
    }
}

/// An app's own New Window command, found in its File menu, for the tile's
/// menu: the Dock's tile menu carries it for apps that offer one — Finder's New
/// Finder Window, Chrome's New Window — and so does this. The app's dock menu
/// itself is its own to give; the menu bar is readable.
@MainActor
struct NewWindowCommand {
    /// The item's wording, as the app has it.
    let title: String
    let element: AXUIElement
    let app: NSRunningApplication

    /// Chooses the item, with the app brought forward so the window lands in front.
    func perform() {
        AppWindows.activate(app)
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

@MainActor
enum AppWindows {
    /// Whether the list can be read at all.
    static var isAvailable: Bool { AXIsProcessTrusted() }

    /// The app's New Window item, from the File menu — by name, or the third
    /// menu after the Apple and app menus where it is called something else:
    /// "New Window" itself, else a "New … Window" that is not a private one. An item that opens a submenu, as Terminal's
    /// does for its profiles, stands for its first entry. Nil when the app has
    /// none, or the item is greyed out right now.
    static func newWindow(of app: NSRunningApplication) -> NewWindowCommand? {
        guard isAvailable, !app.isTerminated else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let menuBar = attribute(kAXMenuBarAttribute, of: application),
              let menus = attribute(kAXChildrenAttribute, of: menuBar as! AXUIElement) as? [AXUIElement],
              let fileMenu = menus.first(where: { attribute(kAXTitleAttribute, of: $0) as? String == "File" })
                  ?? (menus.count > 2 ? menus[2] : nil),
              let file = (attribute(kAXChildrenAttribute, of: fileMenu) as? [AXUIElement])?.first,
              let items = attribute(kAXChildrenAttribute, of: file) as? [AXUIElement] else { return nil }
        var fallback: NewWindowCommand?
        for item in items {
            guard let title = attribute(kAXTitleAttribute, of: item) as? String else { continue }
            let words = title.lowercased().split(separator: " ")
            guard words.first == "new", words.last == "window",
                  !words.contains(where: { ["private", "incognito", "inprivate"].contains($0) }),
                  attribute(kAXEnabledAttribute, of: item) as? Bool ?? true else { continue }
            var command = NewWindowCommand(title: title, element: item, app: app)
            // A submenu's parent does nothing when pressed; its first entry is the default.
            if let submenu = (attribute(kAXChildrenAttribute, of: item) as? [AXUIElement])?.first,
               let first = (attribute(kAXChildrenAttribute, of: submenu) as? [AXUIElement])?.first(where: {
                   attribute(kAXEnabledAttribute, of: $0) as? Bool ?? true
                       && !((attribute(kAXTitleAttribute, of: $0) as? String)?.isEmpty ?? true)
               }) {
                command = NewWindowCommand(title: title, element: first, app: app)
            }
            if words.count == 2 { return command }
            if fallback == nil { fallback = command }
        }
        return fallback
    }

    /// The standard windows of `apps`, front to back as each app reports them,
    /// across every instance. Read when a menu opens; a few round trips per
    /// window, with a timeout so a hung app cannot hold the menu.
    static func windows(of apps: [NSRunningApplication]) -> [AppWindow] {
        guard isAvailable else { return [] }
        var windows: [AppWindow] = []
        for app in apps where !app.isTerminated {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 1)
            let focused = attribute(kAXFocusedWindowAttribute, of: application)
            for element in attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] ?? [] {
                AXUIElementSetMessagingTimeout(element, 1)
                // The Dock lists document and main windows, not palettes and sheets.
                guard attribute(kAXSubroleAttribute, of: element) as? String == kAXStandardWindowSubrole else { continue }
                let title = (attribute(kAXTitleAttribute, of: element) as? String ?? "").trimmingCharacters(in: .whitespaces)
                windows.append(AppWindow(
                    id: windows.count,
                    element: element,
                    app: app,
                    title: title.isEmpty ? (app.localizedName ?? "Untitled") : title,
                    isMinimized: attribute(kAXMinimizedAttribute, of: element) as? Bool ?? false,
                    isFocused: focused.map { CFEqual($0, element) } ?? false
                ))
            }
        }
        return windows
    }

    /// The Dock's Show All Windows: the app comes forward and App Exposé lays
    /// its windows out. Exposé only knows the frontmost app, so it is asked for
    /// once the activation has gone through.
    static func showAll(of app: NSRunningApplication) {
        activate(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["2"]  // 1 shows the desktop, 2 the front app's windows
            configuration.activates = false
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                configuration: configuration
            )
        }
    }

    /// Brings `app` forward. A click on the dock counts as the user's own doing, so
    /// macOS lets the activation through; should it refuse, Launch Services opening
    /// the app again does the same, as a click on the tile does.
    static func activate(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        if !app.activate(), let url = app.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
