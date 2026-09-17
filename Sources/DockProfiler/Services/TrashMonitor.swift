import AppKit
import Combine
import Foundation

/// Whether the user's Trash has anything in it, for the trash widget. Watches
/// `~/.Trash` while a widget is on screen. Recent macOS keeps the folder behind a
/// privacy prompt; until access is granted the count is unknown and the widget
/// shows the empty can.
@MainActor
final class TrashMonitor: ObservableObject {
    static let shared = TrashMonitor()

    /// Items in the Trash, or nil when the folder could not be read.
    @Published private(set) var count: Int?

    var isFull: Bool { (count ?? 0) > 0 }

    static var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    }

    private var source: DispatchSourceFileSystemObject?
    private var rescan: Task<Void, Never>?
    private var subscribers = 0

    private init() {}

    // MARK: - Lifecycle

    /// Watching only runs while at least one widget is on screen.
    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        scan()
        observeDirectory()
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        rescan?.cancel()
        closeSource()
    }

    private func observeDirectory() {
        closeSource()
        let fileDescriptor = Darwin.open(Self.trashURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        self.source = source
    }

    private func closeSource() {
        source?.cancel()
        source = nil
    }

    /// Coalesces the burst of events one move produces.
    private func scheduleScan() {
        rescan?.cancel()
        rescan = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.scan()
        }
    }

    func scan() {
        let items = try? FileManager.default.contentsOfDirectory(
            at: Self.trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        count = items?.count
        // The first scan can run before access is granted; once it is, the watch works.
        if source == nil, items != nil { observeDirectory() }
    }

    // MARK: - Actions

    /// Opens the Trash window in Finder.
    static func reveal() {
        NSWorkspace.shared.open(trashURL)
    }

    /// Moves the files to the Trash, as a drop on the Dock's can does. Returns the
    /// ones that could not be moved.
    @discardableResult
    func trash(_ urls: [URL]) -> [URL] {
        var failed: [URL] = []
        for url in urls where url.isFileURL {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed.append(url)
            }
        }
        scan()
        return failed
    }

    /// Asks Finder to empty the Trash, after confirming. Finder does the work so its
    /// own rules — locked files, other volumes, the warning it may be set to show —
    /// still apply.
    func emptyAfterConfirming() {
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Everything in the Trash will be deleted permanently. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        AppleScriptRunner.run("tell application \"Finder\" to empty trash") { [weak self] result in
            if case .failure(let error) = result {
                let failure = NSAlert()
                failure.messageText = "The Trash could not be emptied"
                failure.informativeText = error.message.isEmpty
                    ? "Finder did not respond. Check that Dock Profiler may control Finder in System Settings › Privacy & Security › Automation."
                    : error.message
                failure.runModal()
            }
            self?.scan()
        }
    }
}
