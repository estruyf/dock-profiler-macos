import AppKit
import Foundation

enum WallpaperError: LocalizedError {
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let path):
            return "The wallpaper “\((path as NSString).lastPathComponent)” could not be found."
        }
    }
}

/// Sets the desktop picture for the Space that is on screen right now, which is
/// why profiles switch desktop first and set the wallpaper second.
enum WallpaperService {
    static func apply(path: String, allScreens: Bool) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw WallpaperError.fileMissing(path)
        }
        let url = URL(fileURLWithPath: path)
        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    static func currentWallpaperPath() -> String? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
    }
}
