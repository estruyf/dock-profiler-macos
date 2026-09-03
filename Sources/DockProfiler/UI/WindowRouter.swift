import Foundation

/// Lets the menu bar tell the manager window which profile to select when it opens.
@MainActor
final class WindowRouter: ObservableObject {
    static let shared = WindowRouter()
    @Published var pendingSelection: UUID?
    /// Set for a freshly created profile so the editor opens its name popover.
    @Published var pendingRename: UUID?
    private init() {}
}
