import Foundation

/// Runs AppleScript in an `osascript` child rather than through `NSAppleScript`,
/// which is main-thread only and blocks for as long as the target app — or the
/// Automation permission prompt macOS puts up the first time — takes to answer.
/// The dock must keep drawing through both.
enum AppleScriptRunner {
    struct Failure: Error {
        var message: String
    }

    /// Runs the script and hands back what it returned, trimmed, on the main actor.
    static func run(_ source: String, completion: @escaping @MainActor (Result<String, Failure>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runSync(source)
            Task { @MainActor in completion(result) }
        }
    }

    /// Runs the script and discards its result.
    static func run(_ source: String) {
        run(source) { _ in }
    }

    private static func runSync(_ source: String) -> Result<String, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // The script goes in on stdin, so nothing in it needs quoting for the shell.
        process.arguments = ["-"]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(Failure(message: error.localizedDescription))
        }
        input.fileHandleForWriting.write(Data(source.utf8))
        try? input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Failure(message: message.isEmpty ? "osascript exited with status \(process.terminationStatus)" : message))
        }
        return .success(String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
