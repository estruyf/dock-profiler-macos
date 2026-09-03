import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The desktop half of a profile: jump to a Space, and/or set the wallpaper there.
struct DesktopOptionsView: View {
    @Binding var options: DesktopOptions
    @ObservedObject private var settings = AppSettings.shared
    @State private var layout: SpaceLayout?
    @State private var hasAccessibility = SpaceService.hasAccessibilityAccess
    @State private var testError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Switch to a desktop when this profile is activated", isOn: $options.switchesSpace)
                if options.switchesSpace {
                    HStack(spacing: 10) {
                        Stepper(value: $options.spaceIndex, in: 1...16) {
                            Text("Desktop \(options.spaceIndex)")
                                .monospacedDigit()
                        }
                        .fixedSize()
                        Button("Test") { test() }
                        Button {
                            layout = SpaceService.layout()
                            hasAccessibility = SpaceService.hasAccessibilityAccess
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Re-read the desktop layout")
                        Spacer()
                    }

                    desktopStrip

                    if !hasAccessibility {
                        permissionNotice
                    }
                    if let testError {
                        Label(testError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("macOS cannot create desktops from an app. Add them once in Mission Control (Control + ↑, then +), and Dock Profiler will jump to the one you pick using \(settings.spaceSwitchMethod.title.lowercased()).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Set a wallpaper when this profile is activated", isOn: $options.setsWallpaper)
                if options.setsWallpaper {
                    HStack(spacing: 12) {
                        wallpaperPreview
                        VStack(alignment: .leading, spacing: 6) {
                            Text(options.wallpaperPath.map { ($0 as NSString).lastPathComponent } ?? "No image chosen")
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 8) {
                                Button("Choose Image…") { chooseWallpaper() }
                                Button("Use Current") {
                                    options.wallpaperPath = WallpaperService.currentWallpaperPath()
                                }
                            }
                        }
                        Spacer()
                    }
                    Toggle("Apply to every display", isOn: $options.wallpaperAllScreens)
                    Text("The wallpaper is set on the desktop that is on screen at that moment — so it lands on the desktop chosen above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            layout = SpaceService.layout()
            hasAccessibility = SpaceService.hasAccessibilityAccess
        }
    }

    private var desktopStrip: some View {
        let count = max(layout?.desktopCount ?? 0, options.spaceIndex)
        return HStack(spacing: 6) {
            ForEach(1...max(count, 1), id: \.self) { index in
                let exists = index <= (layout?.desktopCount ?? 0)
                let isCurrent = (layout?.currentIndex).map { $0 + 1 == index } ?? false
                Button {
                    options.spaceIndex = index
                } label: {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(exists ? Color.accentColor.opacity(options.spaceIndex == index ? 0.75 : 0.18) : Color.gray.opacity(0.1))
                            .frame(width: 44, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        options.spaceIndex == index ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: options.spaceIndex == index ? 2 : 1
                                    )
                            )
                            .overlay(alignment: .topTrailing) {
                                if isCurrent {
                                    Circle().fill(.green).frame(width: 6, height: 6).padding(3)
                                }
                            }
                        Text("\(index)")
                            .font(.caption2)
                            .foregroundStyle(exists ? .primary : .tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help(exists ? (isCurrent ? "Desktop \(index) (current)" : "Desktop \(index)") : "Desktop \(index) does not exist yet")
            }
            Spacer()
        }
    }

    private var permissionNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            Text("Accessibility access is needed to switch desktops.")
                .font(.caption)
            Button("Grant…") {
                SpaceService.requestAccessibilityAccess()
                openAccessibilitySettings()
            }
            .controlSize(.small)
        }
    }

    private var wallpaperPreview: some View {
        Group {
            if let path = options.wallpaperPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: 96, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        options.wallpaperPath = url.path
    }

    private func test() {
        testError = nil
        let index = options.spaceIndex
        let method = settings.spaceSwitchMethod
        Task {
            do {
                try await SpaceService.switchToDesktop(index, method: method)
            } catch {
                testError = error.localizedDescription
                hasAccessibility = SpaceService.hasAccessibilityAccess
            }
            layout = SpaceService.layout()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
