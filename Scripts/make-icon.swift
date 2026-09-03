#!/usr/bin/env swift
//
// Draws Dock Profiler's app icon into an .iconset folder.
//
//   swift Scripts/make-icon.swift <output.iconset>
//
// The mark is the one on the welcome screen: a blue squircle with three Dock
// tiles resting near the bottom, the leading one lit.

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep? {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons leave a margin around the artwork so they line up with Apple's.
    let inset = size * 0.085
    let art = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = art.width * 0.2237

    let squircle = NSBezierPath(roundedRect: art, xRadius: radius, yRadius: radius)
    context.saveGState()
    squircle.addClip()
    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.44, green: 0.62, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.84, alpha: 1),
        ]
    )
    gradient?.draw(in: art, angle: -90)

    // A soft sheen across the top half, the way rounded app icons usually catch light.
    let sheen = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.20),
        NSColor(calibratedWhite: 1, alpha: 0.0),
    ])
    sheen?.draw(in: CGRect(x: art.minX, y: art.midY, width: art.width, height: art.height / 2), angle: -90)
    context.restoreGState()

    // The Dock: a translucent tray holding three tiles.
    let trayWidth = art.width * 0.62
    let trayHeight = art.height * 0.235
    let tray = CGRect(
        x: art.midX - trayWidth / 2,
        y: art.minY + art.height * 0.16,
        width: trayWidth,
        height: trayHeight
    )
    let trayRadius = trayHeight * 0.30
    NSColor(calibratedWhite: 1, alpha: 0.24).setFill()
    NSBezierPath(roundedRect: tray, xRadius: trayRadius, yRadius: trayRadius).fill()

    let gap = tray.width * 0.07
    let tile = (tray.width - gap * 4) / 3
    let tileY = tray.midY - tile / 2
    for index in 0..<3 {
        let rect = CGRect(
            x: tray.minX + gap * CGFloat(index + 1) + tile * CGFloat(index),
            y: tileY, width: tile, height: tile
        )
        NSColor(calibratedWhite: 1, alpha: index == 0 ? 1.0 : 0.62).setFill()
        NSBezierPath(
            roundedRect: rect, xRadius: tile * 0.24, yRadius: tile * 0.24
        ).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// The set Apple asks for: every size at 1x and 2x.
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let rep = drawIcon(size: CGFloat(pixels)),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to render \(pixels)px\n".utf8))
            exit(1)
        }
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try png.write(to: outputDirectory.appendingPathComponent(name))
    }
}

print("wrote \(sizes.count * 2) images to \(outputDirectory.path)")
