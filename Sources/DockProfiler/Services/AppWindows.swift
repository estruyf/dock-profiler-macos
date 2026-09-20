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

@MainActor
enum AppWindows {
    /// Whether the list can be read at all.
    static var isAvailable: Bool { AXIsProcessTrusted() }

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
