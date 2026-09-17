import AppKit
import Foundation

/// What the bundle says about itself, for the About section. The version and
/// build number are stamped into Info.plist by `Scripts/build_app.sh`; a bare
/// `swift run` has no bundle, so everything here has a fallback.
enum AppInfo {
    static let name = "Dock Profiler"

    static let repository = URL(string: "https://github.com/estruyf/dock-profiler-macos")!
    static let changelog = repository.appendingPathComponent("blob/main/CHANGELOG.md")
    static let issues = repository.appendingPathComponent("issues/new")
    static let releases = repository.appendingPathComponent("releases/latest")

    /// The marketing version, e.g. `1.3.0`. `nil` outside a built bundle.
    static var version: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        // Left as the template's placeholder if the plist was copied without sed.
        return value.flatMap { $0.hasPrefix("__") ? nil : $0 }
    }

    /// The build number, e.g. `202609171230`. `nil` outside a built bundle.
    static var build: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return value.flatMap { $0.hasPrefix("__") ? nil : $0 }
    }

    /// `Version 1.3.0 (202609171230)`, or what stands in for it in a dev build.
    static var versionDescription: String {
        guard let version else { return "Development build" }
        if let build { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }

    static var copyright: String {
        (Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)
            ?? "© Elio Struyf. MIT License."
    }

    /// The bundle's icon, or the generic one when there is no bundle.
    static var icon: NSImage { NSApp.applicationIconImage }

    /// Version, build and the macOS it runs on — what a bug report wants pasted in.
    static var diagnosticSummary: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(name) \(versionDescription.replacingOccurrences(of: "Version ", with: ""))\nmacOS \(os)"
    }
}
