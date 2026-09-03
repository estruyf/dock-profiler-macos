// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockProfiler",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DockProfiler",
            path: "Sources/DockProfiler",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
