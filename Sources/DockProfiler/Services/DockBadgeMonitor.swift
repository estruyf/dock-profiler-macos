import AppKit
import ApplicationServices
import Combine

/// The notification badges on the macOS Dock's tiles — WhatsApp's unread count,
/// Mail's — for the custom dock's app tiles. There is no API for another app's
/// badge; the Dock alone knows it. The Dock does expose its tiles through
/// Accessibility, though, each with the badge as its `AXStatusLabel`, so this
/// reads them from there. The parked Dock keeps its tiles, so a combined dock can
/// read them too. It needs Accessibility access, the one privacy permission the
/// app asks for, and only when badges are switched on.
@MainActor
final class DockBadgeMonitor: ObservableObject {
    static let shared = DockBadgeMonitor()

    /// Badge text by bundle identifier, for every Dock tile that has one.
    @Published private(set) var badges: [String: String] = [:]
    /// Whether macOS lets the app read the Dock. Rechecked on every poll and each
    /// time the app comes forward, so granting access in System Settings shows up.
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var poller: Task<Void, Never>?
    private var activationToken: NSObjectProtocol?
    private var subscribers = 0

    private init() {
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrust() }
        }
    }

    // MARK: - Lifecycle

    /// Polling only runs while a dock that shows badges is on screen. macOS puts up
    /// its Accessibility dialog once per app at most, so asking here is a nudge the
    /// first time badges come up without access, and silent after that.
    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        if !isTrusted { requestAccess() }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        poller?.cancel()
        poller = nil
        badges = [:]
    }

    func label(for tile: DockTile) -> String? {
        guard let identifier = tile.bundleIdentifier else { return nil }
        return badges[identifier]
    }

    // MARK: - Access

    func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Asks macOS for Accessibility access. The system puts up its own dialog
    /// the first time; after that only System Settings can grant it.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Reading the Dock

    private func poll() async {
        refreshTrust()
        guard isTrusted else {
            if !badges.isEmpty { badges = [:] }
            return
        }
        // Each attribute is a round trip to the Dock; off the main thread so a slow
        // Dock never stalls the panel.
        let read = await Task.detached(priority: .utility) { DockBadgeReader.badges() }.value
        if read != badges { badges = read }
    }
}

/// Walks the Dock's tiles. Bundle identifiers are cached by path: a tile's URL is
/// the only thing that names its app, and reading the bundle each poll adds up.
private enum DockBadgeReader {
    nonisolated(unsafe) private static var identifiersByPath: [String: String] = [:]

    static func badges() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return [:]
        }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        var badges: [String: String] = [:]
        for list in children(of: application) {
            for item in children(of: list) {
                guard let label = attribute("AXStatusLabel", of: item) as? String, !label.isEmpty,
                      let url = attribute(kAXURLAttribute, of: item) as? URL,
                      let identifier = bundleIdentifier(at: url)
                else { continue }
                badges[identifier] = label
            }
        }
        return badges
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func bundleIdentifier(at url: URL) -> String? {
        if let cached = identifiersByPath[url.path] { return cached }
        guard let identifier = Bundle(url: url)?.bundleIdentifier else { return nil }
        identifiersByPath[url.path] = identifier
        return identifier
    }
}
