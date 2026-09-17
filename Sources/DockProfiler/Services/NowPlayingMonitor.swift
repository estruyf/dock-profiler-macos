import AppKit
import Combine
import Foundation

/// The players the now-playing widget understands: both announce track changes
/// over distributed notifications and take transport commands over Apple Events.
enum MediaPlayer: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    var notificationName: Notification.Name {
        switch self {
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        }
    }

    var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).first
    }

    /// The player's app icon, from its bundle: `NSRunningApplication.icon` is
    /// loaded lazily and can still be nil on the first draw.
    var icon: NSImage? {
        guard let url = runningApplication?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct NowPlayingTrack: Equatable {
    var player: MediaPlayer
    var title: String
    var artist: String
    var album: String = ""
    var isPlaying: Bool

    /// What the artwork is cached under: the same song, playing or paused, has the same art.
    var artworkKey: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

/// What is playing in Music or Spotify. Track changes arrive as distributed
/// notifications, which need no permission; the first read after a widget appears
/// — and the play/pause and skip commands — go over Apple Events, so macOS asks
/// once whether Dock Profiler may control the player.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    static let shared = NowPlayingMonitor()

    @Published private(set) var track: NowPlayingTrack? {
        didSet {
            guard track?.artworkKey != oldValue?.artworkKey else { return }
            loadArtwork()
        }
    }
    /// The current track's album art, once it has been fetched.
    @Published private(set) var artwork: NSImage?

    private var tokens: [NSObjectProtocol] = []
    private var subscribers = 0
    /// Art by `artworkKey`, so skipping back to a song does not fetch it again.
    private var artworkCache: [String: NSImage] = [:]
    private var artworkTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    /// Listening only runs while at least one widget is on screen.
    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        let center = DistributedNotificationCenter.default()
        for player in MediaPlayer.allCases {
            tokens.append(center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.handle(note, from: player) }
            })
        }
        // A player that quits announces nothing; drop its track when it goes.
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let identifier = app?.bundleIdentifier, self.track?.player.rawValue == identifier else { return }
                self.track = nil
            }
        })
        refresh()
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        for token in tokens {
            DistributedNotificationCenter.default().removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
    }

    private func handle(_ note: Notification, from player: MediaPlayer) {
        let info = note.userInfo ?? [:]
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else {
            if track?.player == player { track = nil }
            return
        }
        track = NowPlayingTrack(
            player: player,
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            isPlaying: state == "Playing"
        )
    }

    // MARK: - Apple Events

    /// Reads the current track from whichever players are open, preferring the one
    /// that is playing. Only running players are asked, so nothing gets launched,
    /// and each is asked off the main thread so a slow answer — or the permission
    /// prompt the first time — never stalls the dock.
    func refresh() {
        let players = MediaPlayer.allCases.filter { $0.runningApplication != nil }
        guard !players.isEmpty else {
            track = nil
            return
        }
        let generation = refreshGeneration &+ 1
        refreshGeneration = generation
        var found: [MediaPlayer: NowPlayingTrack?] = [:]
        for player in players {
            AppleScriptRunner.run(Self.currentTrackScript(for: player)) { [weak self] result in
                guard let self, self.refreshGeneration == generation else { return }
                found[player] = Self.parseTrack(try? result.get(), player: player)
                guard found.count == players.count else { return }
                let tracks = players.compactMap { found[$0] ?? nil }
                self.track = tracks.first { $0.isPlaying } ?? tracks.first
            }
        }
    }

    /// Answers that arrive after a newer refresh started are dropped.
    private var refreshGeneration = 0

    private static func currentTrackScript(for player: MediaPlayer) -> String {
        """
        tell application id "\(player.rawValue)"
            set s to player state as string
            if s is "stopped" then return ""
            return s & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (album of current track)
        end tell
        """
    }

    private static func parseTrack(_ text: String?, player: MediaPlayer) -> NowPlayingTrack? {
        guard let text, !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        return NowPlayingTrack(
            player: player,
            title: lines[1],
            artist: lines.count > 2 ? lines[2] : "",
            album: lines.count > 3 ? lines[3] : "",
            isPlaying: lines[0].lowercased() == "playing"
        )
    }

    // MARK: - Artwork

    /// Fetches the album art for the current track: Spotify hands out a URL to
    /// download, Music hands out the bytes, which the script writes to a temporary
    /// file for us to read. Either way the result is cached by song.
    private func loadArtwork() {
        artworkTask?.cancel()
        guard let track else {
            artwork = nil
            return
        }
        let key = track.artworkKey
        if let cached = artworkCache[key] {
            artwork = cached
            return
        }
        artwork = nil
        artworkTask = Task { @MainActor in
            let image = await Self.fetchArtwork(for: track)
            guard !Task.isCancelled, let image else { return }
            self.artworkCache[key] = image
            if self.track?.artworkKey == key { self.artwork = image }
        }
    }

    private static func fetchArtwork(for track: NowPlayingTrack) async -> NSImage? {
        switch track.player {
        case .spotify:
            let script = "tell application id \"\(MediaPlayer.spotify.rawValue)\" to return artwork url of current track"
            guard let text = try? await run(script), let url = URL(string: text) else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        case .music:
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("dockprofiler-artwork-\(UUID().uuidString)")
            let script = """
            tell application id "\(MediaPlayer.music.rawValue)"
                if (count of artworks of current track) is 0 then return ""
                set bytes to raw data of artwork 1 of current track
            end tell
            set f to open for access POSIX file "\(file.path)" with write permission
            set eof f to 0
            write bytes to f
            close access f
            return "ok"
            """
            defer { try? FileManager.default.removeItem(at: file) }
            guard let text = try? await run(script), text == "ok",
                  let data = try? Data(contentsOf: file) else { return nil }
            return NSImage(data: data)
        }
    }

    private static func run(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppleScriptRunner.run(script) { result in
                continuation.resume(with: result)
            }
        }
    }

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    /// Sends a transport command to the player that owns the current track. With
    /// nothing playing, the first player that is open gets it.
    func send(_ command: Command) {
        let player = track?.player ?? MediaPlayer.allCases.first { $0.runningApplication != nil }
        guard let player else { return }
        AppleScriptRunner.run("tell application id \"\(player.rawValue)\" to \(command.rawValue)") { [weak self] _ in
            // Both players announce the change, but a paused player is quiet about a skip.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.refresh()
            }
        }
    }

    /// Brings the player forward.
    func revealPlayer() {
        let player = track?.player ?? MediaPlayer.allCases.first { $0.runningApplication != nil }
        guard let app = player?.runningApplication else { return }
        app.unhide()
        app.activate()
    }
}
