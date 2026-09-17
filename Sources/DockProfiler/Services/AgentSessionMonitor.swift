import AppKit
import Combine
import Foundation

/// What a coding agent is up to, in the terms Agent Frame uses.
enum AgentState: Int, Comparable {
    case idle
    case busy
    case waiting

    static func < (lhs: AgentState, rhs: AgentState) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .busy: return "Working"
        case .waiting: return "Waiting"
        case .idle: return "Idle"
        }
    }

    /// Agent Frame's default frame colours, so the widget and the window agree.
    var color: NSColor {
        switch self {
        case .busy: return NSColor(srgbRed: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255, alpha: 1)
        case .waiting: return NSColor(srgbRed: 0xB2 / 255, green: 0x6A / 255, blue: 0x00 / 255, alpha: 1)
        case .idle: return NSColor(srgbRed: 0x45 / 255, green: 0x5A / 255, blue: 0x64 / 255, alpha: 1)
        }
    }

    /// The Claude Code hook that last fired says what the session is doing.
    init?(hookEvent: String) {
        switch hookEvent {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": self = .busy
        case "Notification", "PermissionRequest": self = .waiting
        case "SessionStart", "Stop": self = .idle
        default: return nil
        }
    }
}

/// One Claude Code session Agent Frame knows about.
struct AgentSession: Identifiable, Hashable {
    var id: String
    var cwd: String
    var state: AgentState
    /// The agent process, when the hook recorded it; lets a crashed session be told apart.
    var pid: pid_t?
    var updatedAt: Date

    var folderName: String { (cwd as NSString).lastPathComponent }
}

/// Reads the session files Agent Frame's Claude Code hooks keep in
/// `~/.agent-frame/sessions` — one JSON file per session, rewritten on every hook
/// event — and publishes the live ones. Nothing is written back: the files belong
/// to Agent Frame, which prunes them itself.
///
/// See https://github.com/estruyf/vscode-agent-frame.
@MainActor
final class AgentSessionMonitor: ObservableObject {
    static let shared = AgentSessionMonitor()

    /// Most urgent first: waiting for you, then working, then idle.
    @Published private(set) var sessions: [AgentSession] = []

    static var sessionsDirectory: URL {
        // DOCKPROFILER_AGENT_SESSIONS_DIR points the widget at demo sessions.
        if let override = ProcessInfo.processInfo.environment["DOCKPROFILER_AGENT_SESSIONS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-frame/sessions", isDirectory: true)
    }

    /// Agent Frame treats sessions untouched for this long as crashed leftovers.
    private static let staleAfter: TimeInterval = 12 * 60 * 60

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var rescan: Task<Void, Never>?
    private var heartbeat: Timer?
    private var subscribers = 0

    private init() {}

    // MARK: - Lifecycle

    /// Watching only runs while at least one widget is on screen.
    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        scan()
        observeDirectory()
        // A session that dies without a SessionEnd never touches its file again, so
        // look for gone processes now and then even when nothing changes on disk.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        heartbeat?.invalidate()
        heartbeat = nil
        rescan?.cancel()
        closeSource()
    }

    private func observeDirectory() {
        closeSource()
        let directory = Self.sessionsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileDescriptor = Darwin.open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        // The hooks write a temp file and `mv` it into place, which shows up as a
        // write on the directory itself.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { [fileDescriptor] in close(fileDescriptor) }
        source.resume()
        self.source = source
    }

    private func closeSource() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    /// Coalesces the burst of events one write produces.
    private func scheduleScan() {
        rescan?.cancel()
        rescan = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            self.scan()
        }
    }

    // MARK: - Reading

    func scan() {
        let directory = Self.sessionsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        var found: [AgentSession] = []
        for file in files where file.pathExtension == "json" {
            guard let session = Self.session(at: file) else { continue }
            found.append(session)
        }
        found.sort { lhs, rhs in
            if lhs.state != rhs.state { return lhs.state > rhs.state }
            return lhs.updatedAt > rhs.updatedAt
        }
        if found != sessions { sessions = found }
    }

    private static func session(at file: URL) -> AgentSession? {
        guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(modified) < staleAfter else { return nil }
        // A hook may be mid-write; the next event re-reads it.
        guard let data = try? Data(contentsOf: file),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["session_id"] as? String,
              let cwd = payload["cwd"] as? String,
              let event = payload["hook_event_name"] as? String,
              let state = AgentState(hookEvent: event) else { return nil }

        var pid: pid_t?
        if let recorded = payload["pid"] as? Int, recorded > 0 {
            pid = pid_t(recorded)
            // ESRCH means the process is gone; EPERM means it exists but is not ours.
            if kill(pid!, 0) != 0, errno == ESRCH { return nil }
        }
        return AgentSession(id: id, cwd: cwd, state: state, pid: pid, updatedAt: modified)
    }

    // MARK: - Opening

    /// Brings the session's editor window forward. The hook records the agent's pid,
    /// and walking up from it reaches the app hosting the session — VS Code, Insiders,
    /// Cursor, or just a terminal — so the folder is opened with that app, which
    /// focuses the window that already has it.
    static func reveal(_ session: AgentSession) {
        let folder = URL(fileURLWithPath: session.cwd, isDirectory: true)
        guard let host = session.pid.flatMap(hostApplication(of:)),
              let bundleURL = host.bundleURL else {
            // No process to trace: fall back to whatever handles folders like VS Code.
            let workspace = NSWorkspace.shared
            let fallback = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
                .lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }.first
            if let fallback {
                workspace.open([folder], withApplicationAt: fallback, configuration: NSWorkspace.OpenConfiguration())
            } else {
                workspace.activateFileViewerSelecting([folder])
            }
            return
        }

        if isEditor(host) {
            NSWorkspace.shared.open([folder], withApplicationAt: bundleURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // A plain terminal has no notion of "the window for this folder".
            host.activate()
        }
    }

    private static func isEditor(_ app: NSRunningApplication) -> Bool {
        guard let identifier = app.bundleIdentifier?.lowercased() else { return false }
        return ["vscode", "cursor", "windsurf", "zed", "jetbrains", "positron"]
            .contains { identifier.contains($0) }
    }

    /// The first ancestor of `pid` that is a regular app.
    static func hostApplication(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<24 {
            guard let parent = parentProcess(of: current), parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent),
               app.activationPolicy == .regular {
                return app
            }
            current = parent
        }
        return nil
    }

    private static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
