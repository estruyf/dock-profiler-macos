import Darwin
import Foundation

/// A coding agent the dock knows how to spot running on this Mac.
enum AgentTool: String, Codable, Hashable {
    case claudeCode
    case codex

    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// The command the tool is run as, and the folder its own installs live in.
    fileprivate var command: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        }
    }

    /// Where the tool keeps a folder per project it has worked in. Only the names
    /// and the modification times are ever read — never what is inside them.
    fileprivate var transcriptsDirectory: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode: return home.appendingPathComponent(".claude/projects", isDirectory: true)
        case .codex: return nil
        }
    }
}

/// One agent found running on this Mac: the process, the folder it was started in,
/// and the session it says it is on.
struct AgentProcess {
    var pid: pid_t
    var tool: AgentTool
    var cwd: String
    /// The session id from the command line, where the tool puts one there. Two
    /// agents in the same folder are then still two sessions.
    var sessionID: String?
}

/// Finds the coding agents running on this Mac, so the Agents widget has something
/// to show without Agent Frame's hooks in the picture.
///
/// Everything here is process and file *metadata*: which processes are running,
/// what they were started as, the folder each is in, and when a transcript file was
/// last written. No transcript is ever opened, so nothing of a conversation, a
/// prompt or generated code is read.
///
/// What this cannot tell you is whether an agent is waiting for an answer: nothing
/// outside the agent says so. A session found this way is working or idle; Agent
/// Frame's hooks, when they are there, still report all three.
enum AgentProcesses {
    /// How recently a session's transcript must have been written for the session
    /// to count as working. Long enough to cover the gaps between an agent's
    /// writes, short enough that a session left alone settles quickly.
    static let busyWithin: TimeInterval = 8

    /// Every agent session running for this user, one per session: a process whose
    /// own children include another agent is the shell a session runs under — the
    /// child is the session — so only the leaves of the tree are returned.
    static func running() -> [AgentProcess] {
        guard let reader = ArgumentReader() else { return [] }
        var found: [pid_t: AgentProcess] = [:]
        var parents: [pid_t: pid_t] = [:]
        for pid in allPIDs() {
            guard let arguments = reader.arguments(of: pid), let executable = arguments.first else { continue }
            let argv0 = arguments.count > 1 ? arguments[1] : ""
            guard let tool = tool(executable: executable, argv0: argv0) else { continue }
            guard let cwd = workingDirectory(of: pid) else { continue }
            found[pid] = AgentProcess(
                pid: pid,
                tool: tool,
                cwd: cwd,
                sessionID: sessionID(in: arguments.dropFirst(2))
            )
            if let parent = parentProcess(of: pid) { parents[pid] = parent }
        }
        let hosts = Set(parents.filter { found[$0.value] != nil }.map(\.value))
        return found.values.filter { !hosts.contains($0.pid) }.sorted { $0.pid < $1.pid }
    }

    /// When the tool last wrote to its record of this folder's work — the file's
    /// modification time, not a line of what is in it. Nil when the tool keeps no
    /// such record, or has not written one for this folder yet.
    static func lastActivity(of process: AgentProcess) -> Date? {
        guard let directory = process.tool.transcriptsDirectory else { return nil }
        let folder = directory.appendingPathComponent(projectFolderName(for: process.cwd), isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            .max()
    }

    /// Claude Code names a project's folder after its path with every character
    /// that is not a letter or a digit turned into a dash, so
    /// `/Users/me/.dotfiles` becomes `-Users-me--dotfiles`.
    static func projectFolderName(for path: String) -> String {
        String(path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    // MARK: - Recognising an agent

    /// Whether the process is one of the agents: run as `claude` or `codex`,
    /// whatever the path, or one of the versioned binaries the tools install for
    /// themselves and run under a path of their own.
    private static func tool(executable: String, argv0: String) -> AgentTool? {
        for tool in [AgentTool.claudeCode, .codex] {
            let command = tool.command
            if argv0 == command || argv0.hasSuffix("/" + command) { return tool }
            if executable.hasSuffix("/" + command) { return tool }
            if executable.contains("/.local/share/\(command)/versions/") { return tool }
        }
        return nil
    }

    /// The session id on the command line: the tools name it either with a flag of
    /// their own or at the end of the session URL they are given.
    private static func sessionID<Arguments: Sequence<String>>(in arguments: Arguments) -> String? {
        var previous: String?
        for argument in arguments {
            defer { previous = argument }
            if previous == "--session-id" || previous == "--resume" { return argument }
            if argument.hasPrefix("--session-id=") { return String(argument.dropFirst("--session-id=".count)) }
            if argument.contains("/sessions/"), let last = argument.split(separator: "/").last, !last.isEmpty {
                return String(last)
            }
        }
        return nil
    }

    // MARK: - Asking the kernel

    private static func allPIDs() -> [pid_t] {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for the processes that start between the two calls.
        count += 64
        var pids = [pid_t](repeating: 0, count: Int(count))
        let bytes = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size) * count)
        guard bytes > 0 else { return [] }
        return Array(pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    /// Reads a process's command line. The kernel answers into a buffer the size of
    /// `ARGMAX` — a megabyte — so the buffer is allocated once and reused for the
    /// whole sweep: a fresh one per process turned a 4 ms scan into a 200 ms one.
    /// Only processes running as this user answer; everything else is left alone.
    private final class ArgumentReader {
        private let capacity: Int
        private let buffer: UnsafeMutablePointer<CChar>

        init?() {
            var maximum: Int32 = 0
            var size = MemoryLayout<Int32>.size
            var limits: [Int32] = [CTL_KERN, KERN_ARGMAX]
            guard sysctl(&limits, 2, &maximum, &size, nil, 0) == 0, maximum > 0 else { return nil }
            capacity = Int(maximum)
            buffer = .allocate(capacity: capacity)
        }

        deinit { buffer.deallocate() }

        /// The executable's path followed by its arguments.
        func arguments(of pid: pid_t) -> [String]? {
            var size = capacity
            var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            guard sysctl(&name, 3, buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

            var count: Int32 = 0
            memcpy(&count, buffer, MemoryLayout<Int32>.size)
            var index = MemoryLayout<Int32>.size

            // The path, then padding, then argv — each null-terminated, with runs
            // of nulls between them.
            func next() -> String? {
                while index < size, buffer[index] == 0 { index += 1 }
                guard index < size else { return nil }
                let start = index
                while index < size, buffer[index] != 0 { index += 1 }
                return String(decoding: UnsafeRawBufferPointer(start: buffer + start, count: index - start), as: UTF8.self)
            }

            guard let executable = next() else { return nil }
            var result = [executable]
            for _ in 0..<count {
                guard let argument = next() else { break }
                result.append(argument)
            }
            return result
        }
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let read = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, Int32(size))
        }
        guard read == Int32(size) else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty || path == "/" ? nil : path
    }

    private static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }
}
