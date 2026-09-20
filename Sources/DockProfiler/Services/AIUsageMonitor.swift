import AppKit
import Combine
import Foundation
import Security

// MARK: - What a service reports

/// One rate-limit window of a service: how much of it is left and when it starts over.
struct UsageWindow: Equatable, Identifiable {
    var id: String
    var title: String
    /// 0–100, what is still available.
    var remaining: Double
    var resetsAt: Date?
    /// The reset is a calendar day rather than a moment, as Copilot's monthly one is.
    var resetsOnDay = false
    /// The count behind the percentage, when there is one: "202 of 300 left".
    var detail: String?
    /// Counts towards the tile's number: the main windows, not the per-model extras.
    var isPrimary = true
}

struct UsageReport: Equatable {
    var service: UsageService
    var windows: [UsageWindow]
    var plan: String?
    var fetchedAt: Date

    /// What the tile shows: the tightest of the main windows.
    var lowestRemaining: Double? {
        windows.filter(\.isPrimary).map(\.remaining).min()
    }
}

/// Why a service has nothing to show.
enum UsageProblem: Equatable {
    /// No token on this Mac: the service's own tool has not been signed in to.
    case signedOut
    /// The Keychain item is there but macOS would not hand it over.
    case keychainDenied
    /// The token was refused: it has expired, or lacks the scope the usage call needs.
    case unauthorized
    case failed(String)

    /// Clears by itself once the service's own tool has signed in again, so it is worth
    /// looking for that rather than waiting to be asked.
    var awaitsSignIn: Bool {
        switch self {
        case .signedOut, .unauthorized: return true
        case .keychainDenied, .failed: return false
        }
    }

    var title: String {
        switch self {
        case .signedOut: return "Not signed in"
        case .keychainDenied: return "Keychain access denied"
        case .unauthorized: return "Sign-in expired"
        case .failed: return "Couldn't refresh"
        }
    }

    func hint(for service: UsageService) -> String {
        switch self {
        case .signedOut: return service.signInHint
        case .keychainDenied: return "Allow Dock Profiler to read the Claude Code-credentials item when macOS asks"
        case .unauthorized:
            switch service {
            case .claude: return "Run Claude Code once so it refreshes its sign-in"
            case .copilot: return "Sign in to GitHub Copilot again in VS Code or Xcode"
            }
        case .failed(let message): return message
        }
    }
}

enum UsageError: Error {
    case signedOut
    case keychainDenied
    case unauthorized
    case badResponse(String)
}

// MARK: - The monitor

/// What is left of the Claude and GitHub Copilot allowances, read the way each
/// service's own tools leave their sign-in on this Mac: Claude Code's OAuth token in
/// the Keychain, Copilot's in `~/.config/github-copilot`. Refreshed every few
/// minutes while a widget is on screen, and on demand.
@MainActor
final class AIUsageMonitor: ObservableObject {
    static let shared = AIUsageMonitor()

    @Published private(set) var reports: [UsageService: UsageReport] = [:]
    /// Why a service has no report — or why its last refresh failed, if it has one.
    @Published private(set) var problems: [UsageService: UsageProblem] = [:]
    @Published private(set) var refreshing: Set<UsageService> = []

    /// Often enough to catch a window resetting, seldom enough not to bother the APIs.
    static let interval: TimeInterval = 5 * 60
    /// While a service waits on its own tool to sign in again, its credentials are
    /// re-read this often, so the new sign-in shows up without a click. The read is
    /// local; the API is only asked again once the token is no longer the one it refused.
    static let retryInterval: TimeInterval = 20

    private var subscribers = 0
    private var timer: Timer?
    private var retryTimer: Timer?
    private var tasks: [UsageService: Task<Void, Never>] = [:]
    /// The token each service refused, so a retry can tell a fresh sign-in from it.
    private var refused: [UsageService: String] = [:]
    private var wakeToken: NSObjectProtocol?

    private init() {}

    // MARK: Lifecycle

    /// Polling only runs while at least one widget is on screen.
    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // A Mac that slept through a reset should not show the old numbers until the next tick.
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
        stopRetrying()
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        wakeToken = nil
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        refreshing.removeAll()
    }

    // MARK: Refreshing

    /// Fetches every service, or just the one. A fetch already under way is left to finish.
    func refresh(_ only: UsageService? = nil) {
        let services = only.map { [$0] } ?? UsageService.allCases
        for service in services { fetch(service, unlessRefused: false) }
    }

    /// Looks again at the services waiting on a new sign-in, asking the API only
    /// when the token on this Mac is no longer the one it refused.
    private func retry() {
        let waiting = UsageService.allCases.filter { problems[$0]?.awaitsSignIn == true }
        guard !waiting.isEmpty else { return stopRetrying() }
        for service in waiting { fetch(service, unlessRefused: true) }
    }

    private func startRetrying() {
        guard retryTimer == nil, subscribers > 0 else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retry() }
        }
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func fetch(_ service: UsageService, unlessRefused: Bool) {
        guard tasks[service] == nil else { return }
        refreshing.insert(service)
        let refused = unlessRefused ? refused[service] : nil
        tasks[service] = Task { [weak self] in
            let outcome = await Self.fetch(service, unless: refused)
            guard !Task.isCancelled else { return }
            self?.finish(service, with: outcome)
        }
    }

    private func finish(_ service: UsageService, with outcome: Outcome) {
        tasks[service] = nil
        refreshing.remove(service)
        switch outcome {
        case .stillRefused:
            break
        case .report(let report):
            reports[service] = report
            problems[service] = nil
            refused[service] = nil
        case .problem(let error, let token):
            let problem = Self.problem(for: error)
            problems[service] = problem
            // A token that no longer works means the numbers behind it are gone too.
            if case UsageError.unauthorized = error { reports[service] = nil }
            if case UsageError.signedOut = error { reports[service] = nil }
            // Only a token the server turned down is worth remembering: one that
            // expired on this Mac never went out, and re-reading it costs nothing.
            refused[service] = problem == .unauthorized ? token : nil
            if problem.awaitsSignIn { startRetrying() }
        }
    }

    private static func problem(for error: Error) -> UsageProblem {
        switch error {
        case UsageError.signedOut: return .signedOut
        case UsageError.keychainDenied: return .keychainDenied
        case UsageError.unauthorized: return .unauthorized
        case UsageError.badResponse(let why): return .failed(why)
        case let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost:
            return .failed("No internet connection")
        default: return .failed(error.localizedDescription)
        }
    }

    private enum Outcome {
        case report(UsageReport)
        /// The token, when the request went out with one: the server refused it.
        case problem(Error, token: String?)
        /// The token is still the one the service refused; nothing was asked.
        case stillRefused
    }

    /// Off the main actor: reading the Keychain can block on a permission dialog.
    private nonisolated static func fetch(_ service: UsageService, unless refused: String?) async -> Outcome {
        var token: String?
        do {
            let current: String
            switch service {
            case .claude: current = try ClaudeUsageSource.token()
            case .copilot: current = try CopilotUsageSource.token()
            }
            if current == refused { return .stillRefused }
            token = current
            switch service {
            case .claude: return .report(try await ClaudeUsageSource.fetch(token: current))
            case .copilot: return .report(try await CopilotUsageSource.fetch(token: current))
            }
        } catch {
            return .problem(error, token: token)
        }
    }
}

// MARK: - Shared plumbing

private enum UsageHTTP {
    /// GETs the URL and returns the JSON object, mapping 401 and 403 to `unauthorized`.
    static func json(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 401, 403: throw UsageError.unauthorized
        default: throw UsageError.badResponse("The server answered \(status)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.badResponse("The reply was not the JSON expected")
        }
        return object
    }

    /// Timestamps come with and without fractional seconds.
    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let string as String: return Double(string)
        default: return nil
        }
    }
}

// MARK: - Claude

/// Claude Code keeps its OAuth token in the Keychain under `Claude Code-credentials`
/// (older builds, and Linux, in `~/.claude/.credentials.json`), and Anthropic's
/// OAuth usage endpoint reports the rate-limit windows that token is subject to.
/// The token is only ever read: refreshing it here would rotate the refresh token
/// out from under Claude Code and sign it out.
enum ClaudeUsageSource {
    static let keychainService = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(token: String) async throws -> UsageReport {
        let json = try await UsageHTTP.json(usageURL, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        ])
        var windows: [UsageWindow] = []
        func add(_ key: String, _ title: String, primary: Bool) {
            guard let window = json[key] as? [String: Any],
                  let used = UsageHTTP.number(window["utilization"]) else { return }
            windows.append(UsageWindow(
                id: key,
                title: title,
                remaining: max(0, min(100, 100 - used)),
                resetsAt: UsageHTTP.date(window["resets_at"] as? String),
                isPrimary: primary
            ))
        }
        add("five_hour", "5 hours", primary: true)
        add("seven_day", "Weekly", primary: true)
        // Per-model weekly windows come in `limits` with the model named; older
        // replies had fixed keys for Opus and Sonnet instead.
        let limits = json["limits"] as? [[String: Any]] ?? []
        for limit in limits where limit["kind"] as? String == "weekly_scoped" {
            guard let percent = UsageHTTP.number(limit["percent"]),
                  let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                  !model.isEmpty else { continue }
            windows.append(UsageWindow(
                id: "weekly_scoped_\(model)",
                title: "Weekly · \(model)",
                remaining: max(0, min(100, 100 - percent)),
                resetsAt: UsageHTTP.date(limit["resets_at"] as? String),
                isPrimary: false
            ))
        }
        if !windows.contains(where: { $0.id.hasPrefix("weekly_scoped_") }) {
            add("seven_day_opus", "Weekly · Opus", primary: false)
            add("seven_day_sonnet", "Weekly · Sonnet", primary: false)
        }
        guard !windows.isEmpty else { throw UsageError.badResponse("No usage windows in the reply") }
        return UsageReport(service: .claude, windows: windows, plan: nil, fetchedAt: Date())
    }

    // MARK: Credentials

    static func token() throws -> String {
        if let token = try keychainToken() { return token }
        if let token = fileToken() { return token }
        throw UsageError.signedOut
    }

    /// The Keychain item belongs to Claude Code, so the first read brings up macOS's
    /// "wants to use your confidential information" dialog; "Always Allow" settles it.
    ///
    /// There can be more than one item under the name — an older sign-in, or one
    /// holding only MCP server logins, left beside the current one — so every match
    /// is read, newest first, and the first with a live token wins. Asking for a
    /// single match could hand back the stale one and call a signed-in Mac signed out.
    private static func keychainToken() throws -> String? {
        // The secrets cannot come back for several items at once, so the items are
        // listed first — attributes and a reference each — and read one by one.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return nil
        default:
            throw failure(status)
        }
        let items = (result as? [[String: Any]] ?? []).sorted {
            let left = $0[kSecAttrModificationDate as String] as? Date ?? .distantPast
            let right = $1[kSecAttrModificationDate as String] as? Date ?? .distantPast
            return left > right
        }
        // An expired token only counts when no item has a live one.
        var expired: Error?
        for item in items {
            guard let reference = item[kSecValueRef as String] else { continue }
            let read: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecMatchItemList as String: [reference],
                kSecReturnData as String: true,
            ]
            var data: CFTypeRef?
            let status = SecItemCopyMatching(read as CFDictionary, &data)
            guard status == errSecSuccess else {
                if status == errSecItemNotFound { continue }
                throw failure(status)
            }
            guard let data = data as? Data else { continue }
            do {
                if let token = try token(in: data) { return token }
            } catch {
                expired = error
            }
        }
        if let expired { throw expired }
        return nil
    }

    private static func failure(_ status: OSStatus) -> Error {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return UsageError.keychainDenied
        default:
            return UsageError.badResponse("Keychain error \(status)")
        }
    }

    private static func fileToken() -> String? {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? token(in: data)
    }

    /// `{"claudeAiOauth": {"accessToken": "sk-ant-oat…", "expiresAt": <ms>, …}}`.
    /// An item that holds only MCP server logins is as good as signed out.
    private static func token(in data: Data) throws -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        if let expires = UsageHTTP.number(oauth["expiresAt"]), expires / 1000 < Date().timeIntervalSince1970 {
            throw UsageError.unauthorized
        }
        return token
    }
}

// MARK: - Copilot

/// The Copilot extensions for VS Code and Xcode keep their GitHub OAuth token in
/// `~/.config/github-copilot/apps.json` (`hosts.json` before that), and GitHub's
/// internal user endpoint — the one the editors ask for the same numbers — reports
/// the premium-request, chat and completion quotas for the month.
enum CopilotUsageSource {
    static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!

    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/github-copilot", isDirectory: true)
    }

    static func fetch(token: String) async throws -> UsageReport {
        // The endpoint is meant for the editor extensions, so it is asked for as one.
        let json = try await UsageHTTP.json(usageURL, headers: [
            "Authorization": "token \(token)",
            "Accept": "application/json",
            "User-Agent": "GitHubCopilotChat/0.31.0",
            "Editor-Version": "vscode/1.104.0",
            "Editor-Plugin-Version": "copilot-chat/0.31.0",
        ])
        let snapshots = json["quota_snapshots"] as? [String: Any] ?? [:]
        let resetsAt = (json["quota_reset_date"] as? String).flatMap(day(from:))

        var windows: [UsageWindow] = []
        func add(_ key: String, _ title: String, primary: Bool) {
            guard let quota = snapshots[key] as? [String: Any] else { return }
            let unlimited = quota["unlimited"] as? Bool ?? false
            let entitlement = UsageHTTP.number(quota["entitlement"]) ?? 0
            let remaining = UsageHTTP.number(quota["remaining"]) ?? 0
            let percent = unlimited ? 100 : (UsageHTTP.number(quota["percent_remaining"])
                ?? (entitlement > 0 ? remaining / entitlement * 100 : 0))
            var detail: String?
            if unlimited {
                detail = "Unlimited"
            } else if entitlement > 0 {
                detail = "\(Int(remaining.rounded(.down))) of \(Int(entitlement)) left"
                if quota["overage_permitted"] as? Bool == true { detail! += " · overage allowed" }
            }
            windows.append(UsageWindow(
                id: key,
                title: title,
                remaining: max(0, min(100, percent)),
                resetsAt: resetsAt,
                resetsOnDay: true,
                detail: detail,
                isPrimary: primary
            ))
        }
        add("premium_interactions", "Premium requests", primary: true)
        add("chat", "Chat", primary: false)
        add("completions", "Completions", primary: false)
        guard !windows.isEmpty else { throw UsageError.badResponse("No quota in the reply") }
        return UsageReport(service: .copilot, windows: windows, plan: json["copilot_plan"] as? String, fetchedAt: Date())
    }

    // MARK: Credentials

    /// `{"github.com:Iv1.…": {"user": "…", "oauth_token": "gho_…"}}`; the key names
    /// the host and the OAuth app, and there is normally one entry.
    static func token() throws -> String {
        for name in ["apps.json", "hosts.json"] {
            let file = configDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let entries = json.sorted { $0.key.hasPrefix("github.com") && !$1.key.hasPrefix("github.com") }
            for (_, value) in entries {
                if let entry = value as? [String: Any],
                   let token = entry["oauth_token"] as? String, !token.isEmpty {
                    return token
                }
            }
        }
        throw UsageError.signedOut
    }

    /// "2026-10-01": the quota starts over on that day.
    private static func day(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
