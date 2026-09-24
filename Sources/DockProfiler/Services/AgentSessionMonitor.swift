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

/// One coding-agent session: either one Agent Frame's hooks are reporting, or one
/// found running on this Mac.
struct AgentSession: Identifiable, Hashable {
    var id: String
    var cwd: String
    var state: AgentState
    /// The agent process, when the hook recorded it or the session was found by
    /// its process; lets a crashed session be told apart.
    var pid: pid_t?
    var updatedAt: Date
    /// Which agent this is. Agent Frame reports Claude Code alone.
    var tool: AgentTool = .claudeCode
    /// The session was found by its process rather than reported by Agent Frame's
    /// hooks, so it has no way of knowing when the agent is waiting for an answer.
    var isDiscovered = false
    /// Whether `state` is read from something, or is only the neutral default. A
    /// tool that keeps no record this side can read says the session is there and
    /// no more, and saying "Idle" for one hard at work would be worse than saying
    /// nothing.
    var stateIsKnown = true

    var folderName: String { (cwd as NSString).lastPathComponent }

    /// What the session is doing, in a word — or just that it is running, for a
    /// session whose state cannot be read.
    var stateTitle: String { stateIsKnown ? state.title : "Running" }

    /// What the tooltip says about where the session came from.
    var sourceHint: String {
        isDiscovered ? "\(tool.title), running here" : "\(tool.title), via Agent Frame"
    }
}

/// Publishes the coding-agent sessions running on this Mac, from two sources.
///
/// Agent Frame's Claude Code hooks keep a JSON file per session in
/// `~/.agent-frame/sessions`, rewritten on every hook event; those files say
/// exactly what a session is doing, waiting included. Nothing is written back:
/// they belong to Agent Frame, which prunes them itself.
/// See https://github.com/estruyf/vscode-agent-frame.
///
/// Without them — or for a session started outside an editor — the agents are
/// found by their processes instead, so the widget has something to show with
/// nothing installed. Those sessions are working or idle only: see
/// `AgentProcesses` for what is read, and what cannot be known that way.
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
    /// How often the sweep comes round: well inside `AgentProcesses.busyWithin`, so
    /// a session that has stopped working is not still shown as busy.
    private static let heartbeatInterval: TimeInterval = 4

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
        // Sessions found by their processes have nothing watching them at all, and
        // their working-or-idle turns on the last few seconds, so the sweep has to
        // come round often enough to catch it — it costs a few milliseconds.
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
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

    /// Whether sessions found by their processes join the ones Agent Frame reports.
    /// On unless a profile's widget turns it off; a session Agent Frame already has
    /// is never listed twice.
    var includesDiscovered = true {
        didSet { if includesDiscovered != oldValue { scan() } }
    }

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
        if includesDiscovered {
            // Agent Frame's word wins for a folder it is already reporting on: it
            // knows about waiting, and the process would only say "working".
            let reported = Set(found.map(\.cwd))
            found += Self.discovered().filter { !reported.contains($0.cwd) }
        }
        found.sort { lhs, rhs in
            if lhs.state != rhs.state { return lhs.state > rhs.state }
            return lhs.updatedAt > rhs.updatedAt
        }
        if found != sessions { sessions = found }
    }

    /// The agents running on this Mac that Agent Frame is not reporting: working
    /// while the tool has written to its record of that folder a moment ago, idle
    /// otherwise. Nothing here says whether an agent is waiting for an answer, so
    /// none of these sessions is ever marked as waiting.
    private static func discovered() -> [AgentSession] {
        let now = Date()
        return AgentProcesses.running().map { process in
            let activity = AgentProcesses.lastActivity(of: process)
            let busy = activity.map { now.timeIntervalSince($0) < AgentProcesses.busyWithin } ?? false
            return AgentSession(
                id: process.sessionID ?? "pid-\(process.pid)",
                cwd: process.cwd,
                state: busy ? .busy : .idle,
                pid: process.pid,
                updatedAt: activity ?? now,
                tool: process.tool,
                isDiscovered: true,
                stateIsKnown: activity != nil
            )
        }
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
