import Foundation

/// Lets the menu bar tell the manager window which profile to select when it opens.
@MainActor
final class WindowRouter: ObservableObject {
    static let shared = WindowRouter()
    @Published var pendingSelection: UUID?
    /// Set for a freshly created profile so the editor opens its name popover.
    @Published var pendingRename: UUID?
    /// Bumped when something asks the manager to show Settings.
    @Published var settingsRequest = 0
    /// Set for a profile so its editor opens on the Custom Dock tab — from a
    /// right-click on the dock itself.
    @Published var pendingCustomDock: UUID?
    /// With `pendingCustomDock`: the Widgets tab rather than the dock's own — from
    /// a right-click on a widget.
    @Published var pendingWidgets = false
    private init() {}
}
