#!/usr/bin/env swift

import Cocoa
import Foundation

// Generate a placeholder app icon for Book Vault
// Theme: Fantasy vault doors with warm glow

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()

// Get graphics context
guard let context = NSGraphicsContext.current?.cgContext else {
    print("Failed to get graphics context")
    exit(1)
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Background gradient - deep purple/blue
let backgroundColors = [
    NSColor(red: 0.12, green: 0.10, blue: 0.22, alpha: 1.0).cgColor,
    NSColor(red: 0.08, green: 0.06, blue: 0.15, alpha: 1.0).cgColor
]
let backgroundGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: backgroundColors as CFArray,
    locations: [0.0, 1.0]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 512, y: 1024),
    end: CGPoint(x: 512, y: 0),
    options: []
)

// Warm glow from center (behind doors)
let glowColors = [
    NSColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 0.6).cgColor,
    NSColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 0.3).cgColor,
    NSColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 0.0).cgColor
]
let glowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: glowColors as CFArray,
    locations: [0.0, 0.4, 1.0]
)!
context.drawRadialGradient(
    glowGradient,
    startCenter: CGPoint(x: 512, y: 450),
    startRadius: 0,
    endCenter: CGPoint(x: 512, y: 450),
    endRadius: 400,
    options: []
)

// Draw stone arch frame
context.setFillColor(NSColor(red: 0.25, green: 0.22, blue: 0.28, alpha: 1.0).cgColor)

// Outer arch
let archPath = CGMutablePath()
archPath.move(to: CGPoint(x: 150, y: 100))
archPath.addLine(to: CGPoint(x: 150, y: 650))
archPath.addQuadCurve(to: CGPoint(x: 512, y: 900), control: CGPoint(x: 150, y: 850))
archPath.addQuadCurve(to: CGPoint(x: 874, y: 650), control: CGPoint(x: 874, y: 850))
archPath.addLine(to: CGPoint(x: 874, y: 100))
archPath.addLine(to: CGPoint(x: 150, y: 100))
context.addPath(archPath)
context.fillPath()

// Inner arch (cutout for doors) - darker
context.setFillColor(NSColor(red: 0.05, green: 0.04, blue: 0.08, alpha: 1.0).cgColor)
let innerArchPath = CGMutablePath()
innerArchPath.move(to: CGPoint(x: 200, y: 120))
innerArchPath.addLine(to: CGPoint(x: 200, y: 620))
innerArchPath.addQuadCurve(to: CGPoint(x: 512, y: 850), control: CGPoint(x: 200, y: 800))
innerArchPath.addQuadCurve(to: CGPoint(x: 824, y: 620), control: CGPoint(x: 824, y: 800))
innerArchPath.addLine(to: CGPoint(x: 824, y: 120))
innerArchPath.addLine(to: CGPoint(x: 200, y: 120))
context.addPath(innerArchPath)
context.fillPath()

// Left door
context.setFillColor(NSColor(red: 0.35, green: 0.25, blue: 0.18, alpha: 1.0).cgColor)
let leftDoorPath = CGMutablePath()
leftDoorPath.move(to: CGPoint(x: 220, y: 140))
leftDoorPath.addLine(to: CGPoint(x: 220, y: 600))
leftDoorPath.addQuadCurve(to: CGPoint(x: 480, y: 780), control: CGPoint(x: 220, y: 750))
leftDoorPath.addLine(to: CGPoint(x: 480, y: 140))
leftDoorPath.addLine(to: CGPoint(x: 220, y: 140))
context.addPath(leftDoorPath)
context.fillPath()

// Right door (slightly ajar - rotated)
context.saveGState()
context.translateBy(x: 544, y: 140)
context.rotate(by: 0.15) // Slightly open
context.setFillColor(NSColor(red: 0.30, green: 0.22, blue: 0.15, alpha: 1.0).cgColor)
let rightDoorPath = CGMutablePath()
rightDoorPath.move(to: CGPoint(x: 0, y: 0))
rightDoorPath.addLine(to: CGPoint(x: 0, y: 460))
rightDoorPath.addQuadCurve(to: CGPoint(x: 240, y: 620), control: CGPoint(x: 0, y: 590))
rightDoorPath.addLine(to: CGPoint(x: 240, y: 0))
rightDoorPath.addLine(to: CGPoint(x: 0, y: 0))
context.addPath(rightDoorPath)
context.fillPath()
context.restoreGState()

// Door details - metal bands on left door
context.setFillColor(NSColor(red: 0.55, green: 0.50, blue: 0.42, alpha: 1.0).cgColor)
for y in stride(from: 200, to: 700, by: 150) {
    let bandRect = CGRect(x: 230, y: y, width: 240, height: 15)
    context.fill(bandRect)
}

// Door handle/ring on left door
context.setStrokeColor(NSColor(red: 0.75, green: 0.65, blue: 0.45, alpha: 1.0).cgColor)
context.setLineWidth(12)
let ringCenter = CGPoint(x: 440, y: 400)
context.strokeEllipse(in: CGRect(x: ringCenter.x - 30, y: ringCenter.y - 30, width: 60, height: 60))

// Golden light rays coming through the gap
context.setFillColor(NSColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 0.4).cgColor)
let lightPath = CGMutablePath()
lightPath.move(to: CGPoint(x: 500, y: 200))
lightPath.addLine(to: CGPoint(x: 520, y: 800))
lightPath.addLine(to: CGPoint(x: 620, y: 600))
lightPath.addLine(to: CGPoint(x: 560, y: 200))
context.addPath(lightPath)
context.fillPath()

// "BV" monogram at top of arch
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 100, weight: .bold),
    .foregroundColor: NSColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1.0),
    .paragraphStyle: paragraphStyle
]

let text = "BV"
let textRect = CGRect(x: 0, y: 880, width: 1024, height: 120)
text.draw(in: textRect, withAttributes: attributes)

image.unlockFocus()

// Save to file
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG data")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Icon saved to: \(outputPath)")
} catch {
    print("Failed to save icon: \(error)")
    exit(1)
}
