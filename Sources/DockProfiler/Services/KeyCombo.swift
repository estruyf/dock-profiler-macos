import AppKit
import Carbon.HIToolbox

/// A global shortcut, stored the way Carbon wants it so it can be registered
/// without needing Accessibility access.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// What to draw for the key itself, captured when the shortcut was recorded.
    var keyLabel: String

    /// ⌃⌥D. Not ⌘⌥D: that is macOS's own shortcut for hiding the Dock, and a hot
    /// key does not stop the system acting on it too — so it brought the parked
    /// Dock back from behind a combined custom dock every time the switcher opened.
    static let defaultSwitcher = KeyCombo(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(controlKey | optionKey),
        keyLabel: "D"
    )

    /// The default before 1.6, kept only so it can be migrated away.
    static let legacyDefaultSwitcher = KeyCombo(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(optionKey | cmdKey),
        keyLabel: "D"
    )

    /// Whether this is ⌘⌥D, which macOS uses to toggle Dock hiding.
    var togglesDockHiding: Bool {
        keyCode == UInt32(kVK_ANSI_D) && carbonModifiers == UInt32(optionKey | cmdKey)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        // Shift on its own is not enough to keep a shortcut out of the way of typing.
        let meaningful: NSEvent.ModifierFlags = [.control, .option, .command]
        guard !flags.intersection(meaningful).isEmpty else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
        self.keyLabel = Self.label(for: event)
    }

    var displayString: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + keyLabel
    }

    private static func label(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let characters = event.charactersIgnoringModifiers ?? ""
        if characters.isEmpty { return "Key \(event.keyCode)" }
        return characters.uppercased()
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
