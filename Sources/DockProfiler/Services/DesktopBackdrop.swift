import AppKit
import ImageIO

/// How light the desktop is where the dock sits, for the styles that show it
/// through: glass, or no slab at all. White tiles on a white wallpaper are not
/// readable, so the dock takes a light or dark appearance from the picture under
/// it, as the Tahoe Dock and menu bar do.
///
/// Reading the screen itself would need the screen-recording permission, so the
/// desktop picture is read from disk instead and placed as the Finder places it —
/// scaled to fill the screen — and the patch under the slab is averaged. Windows
/// over the desktop are not seen, which is how the Dock's own tinting behaves too.
@MainActor
final class DesktopBackdrop {
    static let shared = DesktopBackdrop()

    /// A small copy of the picture: plenty to average a patch of it, and cheap to
    /// keep and draw. Read again when the file, or the frame of a dynamic
    /// desktop, changes.
    private struct Picture {
        let url: URL
        let modified: Date?
        let dark: Bool
        let image: CGImage?
        /// The picture's full size, which the small copy stands in for.
        let size: NSSize
    }

    private var picture: Picture?

    private init() {}

    /// Whether the desktop is light under `rect`, given in screen coordinates. Nil
    /// when there is no picture to read — an aerial wallpaper, say — in which case
    /// the dock follows the system as before.
    func isLight(under rect: NSRect, on screen: NSScreen) -> Bool? {
        let workspace = NSWorkspace.shared
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let fill = options[.fillColor] as? NSColor
        let picture = workspace.desktopImageURL(for: screen).flatMap { load($0, dark: Self.systemIsDark) }
        guard picture?.image != nil || fill != nil else { return nil }
        // "Fill Screen" is proportional scaling that may clip; "Fit to Screen" may not.
        let scaling = options[.imageScaling] as? Int
        let fit = scaling == Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue) && (options[.allowClipping] as? Bool) == false
        guard let luminance = Self.luminance(
            of: picture, fill: fill, scaling: fit ? .scaleProportionallyUpOrDown : scaling.flatMap { NSImageScaling(rawValue: UInt($0)) },
            fit: fit, under: rect, on: screen.frame
        ) else { return nil }
        return luminance > 0.55
    }

    private static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: - Reading the picture

    private func load(_ url: URL, dark: Bool) -> Picture {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let picture, picture.url == url, picture.modified == modified, picture.dark == dark {
            return picture
        }
        var image: CGImage?
        var size = NSSize.zero
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let frame = Self.frame(in: source, dark: dark)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, frame, options as CFDictionary)
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
               let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
                size = NSSize(width: width, height: height)
            } else if let image {
                size = NSSize(width: image.width, height: image.height)
            }
        }
        let picture = Picture(url: url, modified: modified, dark: dark, image: image, size: size)
        self.picture = picture
        return picture
    }

    /// A dynamic desktop is several pictures in one file, and names its light and
    /// dark ones in its metadata: `apr` for one that follows the appearance, `solar`
    /// for one that follows the sun. The one matching the appearance is the nearest
    /// to what is on screen.
    private static func frame(in source: CGImageSource, dark: Bool) -> Int {
        guard CGImageSourceGetCount(source) > 1,
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return 0 }
        for path in ["apple_desktop:apr", "apple_desktop:solar"] {
            guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
                  let encoded = CGImageMetadataTagCopyValue(tag) as? String,
                  let data = Data(base64Encoded: encoded),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let pair = plist["ap"] as? [String: Any] ?? plist
            if let index = pair[dark ? "d" : "l"] as? Int, index < CGImageSourceGetCount(source) {
                return index
            }
        }
        return 0
    }

    // MARK: - Sampling

    /// The mean luminance, 0 to 1, of the picture under `rect`, drawn onto the fill
    /// colour the way the Finder lays the desktop out on `screen`.
    private static func luminance(of picture: Picture?, fill: NSColor?, scaling: NSImageScaling?, fit: Bool, under rect: NSRect, on screen: NSRect) -> Double? {
        let side = 8
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Map the patch under the slab onto the tiny bitmap, so drawing the picture
        // where it sits on screen leaves just that patch behind.
        context.scaleBy(x: CGFloat(side) / rect.width, y: CGFloat(side) / rect.height)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        if let fill {
            context.setFillColor(fill.cgColor)
            context.fill(screen)
        }
        if let picture, let image = picture.image {
            context.interpolationQuality = .low
            context.draw(image, in: placement(of: picture.size, scaling: scaling, fit: fit, on: screen))
        }

        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        for index in stride(from: 0, to: side * side * 4, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return total / Double(side * side)
    }

    /// Where the picture lands on the screen under the desktop's scaling option:
    /// filling it by default, or fit, stretched or centred at its own size.
    private static func placement(of size: NSSize, scaling: NSImageScaling?, fit: Bool, on screen: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale: NSSize
        switch scaling {
        case .scaleProportionallyUpOrDown where fit:
            let factor = min(screen.width / size.width, screen.height / size.height)
            scale = NSSize(width: factor, height: factor)
        case .scaleAxesIndependently:
            scale = NSSize(width: screen.width / size.width, height: screen.height / size.height)
        case .scaleNone:
            scale = NSSize(width: 1, height: 1)
        default:
            let factor = max(screen.width / size.width, screen.height / size.height)
            scale = NSSize(width: factor, height: factor)
        }
        let drawn = NSSize(width: size.width * scale.width, height: size.height * scale.height)
        return NSRect(
            x: screen.midX - drawn.width / 2,
            y: screen.midY - drawn.height / 2,
            width: drawn.width,
            height: drawn.height
        )
    }
}
