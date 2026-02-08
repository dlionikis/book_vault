#!/usr/bin/env swift
//
//  generate-app-icons.swift
//  BookVault
//
//  Generates app icon PNGs for all color variants at required iOS sizes.
//  Usage: swift ios/scripts/generate-app-icons.swift
//

import AppKit

// MARK: - Icon Color Definitions

struct IconColor {
    let name: String
    let color: NSColor
}

let iconColors: [IconColor] = [
    IconColor(name: "Blue", color: NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)),
    IconColor(name: "Indigo", color: NSColor(red: 0.345, green: 0.337, blue: 0.839, alpha: 1.0)),
    IconColor(name: "Purple", color: NSColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1.0)),
    IconColor(name: "Teal", color: NSColor(red: 0.188, green: 0.690, blue: 0.780, alpha: 1.0)),
    IconColor(name: "Green", color: NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0)),
    IconColor(name: "Orange", color: NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)),
    IconColor(name: "Red", color: NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)),
    IconColor(name: "Graphite", color: NSColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1.0)),
]


// MARK: - Paths

let scriptPath = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iosRoot = scriptPath.deletingLastPathComponent()
let assetsDir = iosRoot.appendingPathComponent("BookVault/Assets.xcassets")
let primaryIconDir = assetsDir.appendingPathComponent("AppIcon.appiconset")

// MARK: - Icon Generation

func generateIcon(color: NSColor, pixelSize: Int) -> Data? {
    // Use a large symbol point size to get maximum rasterization quality,
    // then scale down to the target canvas. This avoids fuzziness from
    // upscaling a low-resolution symbol rasterization.
    let symbolPointSize: CGFloat = 840.0
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("Failed to load SF Symbol")
        return nil
    }

    let symSize = symbol.size

    // Render tinted symbol at full resolution into an NSImage
    let tinted = NSImage(size: symSize)
    tinted.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: symSize).fill()
    symbol.draw(in: NSRect(origin: .zero, size: symSize), from: .zero, operation: .destinationIn, fraction: 1.0)
    tinted.unlockFocus()

    // Create the final bitmap at exact pixel dimensions
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: pixelSize * 4,
        bitsPerPixel: 32
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        print("Failed to create graphics context")
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    // White background
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

    // Scale symbol to fill ~55% of canvas, centered
    let canvasSize = CGFloat(pixelSize)
    let targetSymbolHeight = canvasSize * 0.55
    let scale = targetSymbolHeight / symSize.height
    let drawWidth = symSize.width * scale
    let drawHeight = symSize.height * scale
    let x = (canvasSize - drawWidth) / 2.0
    let y = (canvasSize - drawHeight) / 2.0

    tinted.draw(
        in: NSRect(x: x, y: y, width: drawWidth, height: drawHeight),
        from: .zero, operation: .sourceOver, fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

/// Strip alpha channel using ImageMagick (NSBitmapImageRep opaque fallback is unreliable)
func stripAlpha(at path: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/magick")
    process.arguments = [path.path, "-background", "white", "-alpha", "remove", "-alpha", "off", path.path]
    try? process.run()
    process.waitUntilExit()
}

// MARK: - Asset Catalog Contents.json Template

let contentsJSON = """
{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""

// MARK: - Generate All Icons

print("Generating app icons...")

for iconColor in iconColors {
    guard let iconData = generateIcon(color: iconColor.color, pixelSize: 1024) else {
        print("  FAILED: \(iconColor.name)")
        continue
    }

    let iconSetName = iconColor.name == "Blue" ? "AppIcon" : "AppIcon-\(iconColor.name)"
    let iconSetDir = assetsDir.appendingPathComponent("\(iconSetName).appiconset")

    // Ensure appiconset directory exists
    try FileManager.default.createDirectory(at: iconSetDir, withIntermediateDirectories: true)

    // Write the PNG
    let pngURL = iconSetDir.appendingPathComponent("AppIcon.png")
    try iconData.write(to: pngURL)
    stripAlpha(at: pngURL)

    // Write Contents.json
    let contentsURL = iconSetDir.appendingPathComponent("Contents.json")
    try contentsJSON.data(using: .utf8)!.write(to: contentsURL)

    print("  \(iconSetName).appiconset/AppIcon.png (1024x1024)")
}

print("Done!")
