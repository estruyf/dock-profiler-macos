import Foundation

/// Notices when the Dock's own preferences change — you dragging an app in or
/// out, for instance — so the active profile can follow along.
@MainActor
final class DockWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var debounce: Task<Void, Never>?
    private var onChange: (() -> Void)?
    private var notificationToken: NSObjectProtocol?
    private var isStopped = true

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        isStopped = false
        observeFile()
        notificationToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleChange() }
        }
    }

    func stop() {
        isStopped = true
        debounce?.cancel()
        closeSource()
        if let notificationToken {
            DistributedNotificationCenter.default().removeObserver(notificationToken)
            self.notificationToken = nil
        }
    }

    private func observeFile() {
        closeSource()
        let path = DockService.preferencesFileURL.path
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            // The file may be mid-replacement; try again shortly.
            retryLater()
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                let events = source.data
                self.scheduleChange()
                if events.contains(.rename) || events.contains(.delete) {
                    // Preferences are replaced atomically, so re-attach to the new file.
                    self.retryLater()
                }
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        self.source = source
        source.resume()
    }

    private func retryLater() {
        guard !isStopped else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !self.isStopped else { return }
            self.observeFile()
        }
    }

    private func closeSource() {
        source?.cancel()
        source = nil
    }

    private func scheduleChange() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, !self.isStopped else { return }
            self.onChange?()
        }
    }
}
