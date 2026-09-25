import AppKit
import Darwin

/// Whether the app may read the files the browsers keep their profiles in —
/// Chromium's `Local State`, Firefox's `profiles.ini`. Recent macOS keeps an
/// app's data to that app: the file is there, it can be listed, but opening it
/// fails with EPERM. The profiles then read as none, and a browser tile's menu,
/// a launcher's profile picker and a profile's running dot have nothing to go
/// on. Full Disk Access lets the read through.
///
/// Checked by opening each file, the same read the profiles take, so the answer
/// is the one they would get. Rechecked each time an app comes forward, so access
/// granted in System Settings shows up when the user comes back.
@MainActor
final class BrowserDataAccess: ObservableObject {
    static let shared = BrowserDataAccess()

    enum Status {
        /// Every browser's profiles can be read.
        case allowed
        /// macOS keeps at least one browser's profiles from the app.
        case denied
        /// No browser whose profiles are known has been run on this Mac.
        case noBrowsers
    }

    @Published private(set) var status: Status

    /// Whether a browser's profiles come back empty only because there are none —
    /// true unless macOS is keeping them from the app.
    var isAllowed: Bool { status != .denied }

    private var activationToken: NSObjectProtocol?

    private init() {
        status = Self.check()
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let status = Self.check()
        if status != self.status { self.status = status }
    }

    /// Reads the files again, which is where macOS puts up its own dialog when
    /// it has one for this, and opens Full Disk Access when the read is still
    /// refused — the way in once macOS has said no, or where it never asks.
    func requestAccess() {
        refresh()
        if status == .denied { Self.openSettings() }
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    private static func check() -> Status {
        let files = BrowserProfiles.profileFiles
        guard !files.isEmpty else { return .noBrowsers }
        for file in files {
            let descriptor = open(file.path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
            } else if errno == EPERM || errno == EACCES {
                return .denied
            }
        }
        return .allowed
    }
}
