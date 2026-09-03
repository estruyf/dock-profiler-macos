import ApplicationServices
import CoreGraphics
import Foundation

enum SpaceSwitchMethod: String, Codable, CaseIterable, Identifiable {
    /// Ctrl + ← / → repeated until we land on the target desktop.
    case arrows
    /// Ctrl + <number>, which macOS keeps switched off by default.
    case numberShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrows: return "Arrow navigation"
        case .numberShortcut: return "Control + number"
        }
    }

    var explanation: String {
        switch self {
        case .arrows:
            return "Works out of the box. Dock Profiler reads which desktop you are on and presses Control + ← / → the right number of times."
        case .numberShortcut:
            return "One keystroke, but you must first enable “Switch to Desktop N” under System Settings → Keyboard → Keyboard Shortcuts → Mission Control."
        }
    }
}

struct SpaceInfo: Identifiable, Hashable {
    var id: Int
    var uuid: String
    var isFullscreen: Bool
}

struct SpaceLayout {
    var displayIdentifier: String
    var spaces: [SpaceInfo]
    /// Zero-based position of the desktop currently on screen.
    var currentIndex: Int?

    var desktopCount: Int { spaces.count }
}

enum SpaceError: LocalizedError {
    case needsAccessibility
    case unknownLayout
    case unknownCurrentSpace
    case outOfRange(available: Int)
    case shortcutUnavailable

    var errorDescription: String? {
        switch self {
        case .needsAccessibility:
            return "Dock Profiler needs Accessibility access to switch desktops. Grant it in System Settings → Privacy & Security → Accessibility."
        case .unknownLayout:
            return "Could not read the desktop layout from macOS."
        case .unknownCurrentSpace:
            return "Could not work out which desktop is currently active."
        case .outOfRange(let available):
            return "That desktop does not exist. You currently have \(available) desktop\(available == 1 ? "" : "s") on the main display — add more in Mission Control."
        case .shortcutUnavailable:
            return "Only desktops 1–9 can be reached with the Control + number shortcut."
        }
    }
}

/// Switching Spaces has no public API, so Dock Profiler drives the same keyboard
/// shortcuts a person would use, and reads `com.apple.spaces` (a plain
/// preferences domain) to know where it currently is.
enum SpaceService {
    private static let domain = "com.apple.spaces" as CFString

    // MARK: - Layout

    static func layout() -> SpaceLayout? {
        CFPreferencesAppSynchronize(domain)
        guard let configuration = CFPreferencesCopyAppValue(
            "SpacesDisplayConfiguration" as CFString, domain
        ) as? [String: Any],
            let management = configuration["Management Data"] as? [String: Any],
            let monitors = management["Monitors"] as? [[String: Any]]
        else { return nil }

        let candidates = monitors.filter { ($0["Spaces"] as? [[String: Any]])?.isEmpty == false }
        let monitor = candidates.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? candidates.first
        guard let monitor, let rawSpaces = monitor["Spaces"] as? [[String: Any]] else { return nil }

        let spaces: [SpaceInfo] = rawSpaces.map { space in
            SpaceInfo(
                id: space["id64"] as? Int ?? space["ManagedSpaceID"] as? Int ?? 0,
                uuid: space["uuid"] as? String ?? "",
                isFullscreen: (space["type"] as? Int ?? 0) != 0
            )
        }

        var currentIndex: Int?
        if let current = monitor["Current Space"] as? [String: Any] {
            let currentID = current["id64"] as? Int ?? current["ManagedSpaceID"] as? Int
            currentIndex = spaces.firstIndex { $0.id == currentID }
        }

        return SpaceLayout(
            displayIdentifier: monitor["Display Identifier"] as? String ?? "Main",
            spaces: spaces,
            currentIndex: currentIndex
        )
    }

    // MARK: - Permission

    static var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Switching

    /// `index` is 1-based, matching what macOS calls "Desktop 1", "Desktop 2", …
    static func switchToDesktop(_ index: Int, method: SpaceSwitchMethod) async throws {
        guard hasAccessibilityAccess else { throw SpaceError.needsAccessibility }

        switch method {
        case .numberShortcut:
            guard let key = numberKeyCode(for: index) else { throw SpaceError.shortcutUnavailable }
            post(key: key)
        case .arrows:
            guard let layout = layout() else { throw SpaceError.unknownLayout }
            guard index >= 1, index <= layout.desktopCount else {
                throw SpaceError.outOfRange(available: layout.desktopCount)
            }
            guard let current = layout.currentIndex else { throw SpaceError.unknownCurrentSpace }
            let steps = (index - 1) - current
            guard steps != 0 else { return }
            let key: CGKeyCode = steps > 0 ? 124 : 123  // right / left arrow
            for _ in 0..<abs(steps) {
                post(key: key)
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
        }
    }

    private static func numberKeyCode(for index: Int) -> CGKeyCode? {
        let codes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]  // 1…9
        guard index >= 1, index <= codes.count else { return nil }
        return codes[index - 1]
    }

    private static func post(key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskControl
        up?.flags = .maskControl
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
