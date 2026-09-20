import AppKit
import SwiftUI

// Renders the README screenshots from the real views, driven by a set of demo
// profiles written to DOCKPROFILER_STORE_DIR. Run it through Scripts/make_screenshots.sh.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/screenshots"

// MARK: - Demo data

private struct StoreFile: Encodable {
    var profiles: [DockProfile]
    var activeProfileID: UUID?
}

/// The custom dock the shots use: the glanceable widgets plus the Trash and a
/// Downloads stack — the ones that draw without a player, a sign-in or an agent
/// running on this Mac.
@MainActor
func demoDock(mode: CustomDockMode) -> CustomDockOptions {
    var dock = CustomDockOptions()
    dock.enabled = true
    dock.mode = mode
    dock.alignment = .center
    var downloads = WidgetTile(kind: .folderStack)
    downloads.path = NSHomeDirectory() + "/Downloads"
    dock.widgets = [
        WidgetTile(kind: .clock),
        WidgetTile(kind: .date),
        WidgetTile(kind: .battery),
        WidgetTile(kind: .trash),
        downloads,
    ]
    return dock
}

@MainActor
func writeDemoProfiles() {
    func tiles(_ paths: [String]) -> [DockTile] {
        paths.compactMap { path in
            path == "|" ? DockTile.spacer(.smallSpacer) : DockTile.app(at: URL(fileURLWithPath: path))
        }
    }

    var development = DockProfile(name: "Development")
    development.color = .blue
    development.symbol = "chevron.left.forwardslash.chevron.right"
    development.apps = tiles([
        "/System/Library/CoreServices/Finder.app",
        "/Applications/Visual Studio Code.app",
        "/Applications/Ghostty.app",
        "/Applications/Google Chrome.app",
        "|",
        "/Applications/Slack.app",
        "/System/Applications/Notes.app",
    ])
    development.customDock = demoDock(mode: .combined)

    var design = DockProfile(name: "Design")
    design.color = .pink
    design.symbol = "paintbrush"
    design.apps = tiles([
        "/System/Library/CoreServices/Finder.app",
        "/System/Applications/Photos.app",
        "/Applications/Safari.app",
        "|",
        "/System/Applications/Music.app",
    ])

    var focus = DockProfile(name: "Focus")
    focus.color = .purple
    focus.symbol = "moon.stars"
    focus.apps = tiles([
        "/System/Applications/Notes.app",
        "/System/Applications/Reminders.app",
        "/System/Applications/Calendar.app",
    ])

    var meetings = DockProfile(name: "Meetings")
    meetings.color = .orange
    meetings.symbol = "video"
    meetings.apps = tiles([
        "/System/Applications/Calendar.app",
        "/Applications/Slack.app",
        "/System/Applications/Mail.app",
        "/Applications/Safari.app",
    ])

    let file = StoreFile(profiles: [development, design, focus, meetings], activeProfileID: development.id)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let directory = ProcessInfo.processInfo.environment["DOCKPROFILER_STORE_DIR"],
          let data = try? encoder.encode(file) else { return }
    let url = URL(fileURLWithPath: directory).appendingPathComponent("profiles.json")
    try? FileManager.default.createDirectory(
        at: URL(fileURLWithPath: directory), withIntermediateDirectories: true
    )
    try? data.write(to: url)
}

// MARK: - Capture

/// Renders a view in a real window off-screen and returns the window's own
/// image — chrome included when the window is titled.
@MainActor
func snapshot<V: View>(
    _ view: V,
    appearance: NSAppearance.Name,
    size: NSSize?,
    titled: Bool
) -> NSImage? {
    let hosting = NSHostingController(rootView: AnyView(view))
    let window = NSWindow(contentViewController: hosting)
    window.appearance = NSAppearance(named: appearance)
    window.styleMask = titled
        ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        : [.borderless]
    if titled {
        window.title = "Dock Profiler"
        window.titleVisibility = .hidden
    }
    if let size { window.setContentSize(size) }
    window.backgroundColor = titled ? nil : .clear
    window.isOpaque = !titled ? false : true
    // Rendered off-screen, so running this never disturbs what you are doing.
    // The window draws in its inactive state — grey traffic lights, unemphasised
    // selection — which capturing on-screen does not change either.
    window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
    window.orderFront(nil)
    window.makeKey()

    RunLoop.main.run(until: Date().addingTimeInterval(1.0))

    // The theme frame is the whole window, titlebar and rounded corners and all.
    let target = titled ? (hosting.view.superview ?? hosting.view) : hosting.view
    target.layoutSubtreeIfNeeded()
    target.displayIfNeeded()
    guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return nil }
    target.cacheDisplay(in: target.bounds, to: rep)
    window.orderOut(nil)

    let image = NSImage(size: target.bounds.size)
    image.addRepresentation(rep)
    return image
}

/// Drops the window onto a soft gradient with a shadow under it.
@MainActor
func compose(_ window: NSImage, padding: CGFloat, top: NSColor, bottom: NSColor) -> NSImage {
    let size = NSSize(
        width: window.size.width + padding * 2,
        height: window.size.height + padding * 2
    )
    let canvas = NSImage(size: size)
    canvas.lockFocus()

    NSGradient(colors: [top, bottom])?.draw(
        in: NSRect(origin: .zero, size: size), angle: -90
    )

    let frame = NSRect(
        x: padding, y: padding, width: window.size.width, height: window.size.height
    )
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = padding * 0.55
    shadow.shadowOffset = NSSize(width: 0, height: -padding * 0.16)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    window.draw(in: frame)
    NSGraphicsContext.current?.restoreGraphicsState()

    canvas.unlockFocus()
    return canvas
}

@MainActor
func write(_ image: NSImage, named name: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("failed to encode \(name)")
        return
    }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(name)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? png.write(to: url)
    print("wrote \(name) — \(Int(image.size.width))×\(Int(image.size.height))")
}

// MARK: - The shots

@MainActor
func run() {
    writeDemoProfiles()

    let store = ProfileStore.shared
    print("demo profiles: \(store.profiles.map(\.name))")

    let dusk = (NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.72, alpha: 1),
                NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.45, alpha: 1))
    let day = (NSColor(calibratedRed: 0.78, green: 0.83, blue: 0.93, alpha: 1),
               NSColor(calibratedRed: 0.62, green: 0.69, blue: 0.86, alpha: 1))

    if let manager = snapshot(
        ProfilesWindow().environmentObject(store),
        appearance: .aqua, size: NSSize(width: 1080, height: 640), titled: true
    ) {
        write(compose(manager, padding: 56, top: day.0, bottom: day.1), named: "manager.png")
    }

    let model = SwitcherModel()
    model.reset()
    if let switcher = snapshot(
        SwitcherView(model: model, onActivate: { _ in }).environmentObject(store),
        appearance: .darkAqua, size: nil, titled: false
    ) {
        write(compose(switcher, padding: 64, top: dusk.0, bottom: dusk.1), named: "switcher.png")
    }

    if let menuBar = snapshot(
        MenuBarContentView().environmentObject(store)
            .background(Color(nsColor: .windowBackgroundColor)),
        appearance: .darkAqua, size: nil, titled: false
    ) {
        write(compose(menuBar, padding: 48, top: dusk.0, bottom: dusk.1), named: "menubar.png")
    }

    // The custom dock, as the panel draws it: the Development profile's apps and
    // widgets in one row, dark glass, and the same dock stood on its side.
    if let development = store.profiles.first(where: { $0.name == "Development" }) {
        var look = DockLook()
        look.style = .dark
        if let dock = snapshot(
            CustomDockView(items: development.appRow, edge: .bottom, tileSize: 56, look: look)
                .padding(24),
            appearance: .darkAqua, size: nil, titled: false
        ) {
            write(compose(dock, padding: 40, top: dusk.0, bottom: dusk.1), named: "custom-dock.png")
        }

        var light = DockLook()
        light.style = .light
        if let column = snapshot(
            CustomDockView(items: development.appRow, edge: .leading, tileSize: 48, look: light)
                .padding(24),
            appearance: .aqua, size: nil, titled: false
        ) {
            write(compose(column, padding: 40, top: day.0, bottom: day.1), named: "custom-dock-column.png")
        }
    }

    if let welcome = snapshot(
        WelcomeView(onFinish: { _ in }).environmentObject(store),
        appearance: .aqua, size: nil, titled: true
    ) {
        write(compose(welcome, padding: 56, top: day.0, bottom: day.1), named: "welcome.png")
    }
}

MainActor.assumeIsolated { run() }
