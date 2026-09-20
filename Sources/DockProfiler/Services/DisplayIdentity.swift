import AppKit

/// Telling displays apart. `NSScreen` objects are remade whenever the display
/// layout changes and a display's number can change when it is plugged back in,
/// so settings for a display are kept under an id that survives both.
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The display's UUID, the same each time the same display is connected. Nil
    /// only if the display cannot be identified at all.
    var persistentID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The best key there is for this display: its UUID, else its number, else its name.
    var displayKey: String {
        persistentID ?? displayID.map { "display-\($0)" } ?? localizedName
    }

    /// Whether this is the main display, the one with the menu bar.
    var isMain: Bool { self == NSScreen.screens.first }
}
