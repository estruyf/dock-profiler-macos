import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The desktop half of a profile: the wallpaper to set when it is activated.
struct DesktopOptionsView: View {
    @Binding var options: DesktopOptions

    var body: some View {
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
                Text("The wallpaper is set on the desktop that is on screen at that moment. Dock Profiler needs no permissions for this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
}
