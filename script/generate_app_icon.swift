#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Sources/PeakHalo/Resources", isDirectory: true)
let assetsURL = rootURL.appendingPathComponent("Assets", isDirectory: true)
let iconsetURL = assetsURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let logoURL = resourcesURL.appendingPathComponent("AppLogo.png")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: iconsetURL.path) {
    try FileManager.default.removeItem(at: iconsetURL)
}
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(size pixelSize: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    let size = CGFloat(pixelSize)
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let cardRect = bounds.insetBy(dx: size * 0.055, dy: size * 0.055)
    let cornerRadius = size * 0.215
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = max(6, size * 0.055)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    shadow.set()
    NSColor(calibratedRed: 0.035, green: 0.052, blue: 0.073, alpha: 1).setFill()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.080, green: 0.125, blue: 0.165, alpha: 1),
        NSColor(calibratedRed: 0.020, green: 0.032, blue: 0.050, alpha: 1)
    ])?.draw(in: cardPath, angle: 315)

    NSGraphicsContext.saveGraphicsState()
    cardPath.addClip()

    let washRect = NSRect(
        x: size * 0.04,
        y: size * 0.46,
        width: size * 0.86,
        height: size * 0.48
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.82, alpha: 0.22),
        NSColor.clear
    ])?.draw(in: NSBezierPath(ovalIn: washRect), relativeCenterPosition: NSPoint(x: -0.2, y: 0.1))

    NSGraphicsContext.restoreGraphicsState()

    let primaryMint = NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.76, alpha: 1)
    let brightMint = NSColor(calibratedRed: 0.58, green: 0.98, blue: 0.92, alpha: 1)
    let accentMint = NSColor(calibratedRed: 0.25, green: 0.66, blue: 0.78, alpha: 1)
    let deepMint = NSColor(calibratedRed: 0.73, green: 1.0, blue: 0.94, alpha: 1)

    let center = NSPoint(x: size * 0.50, y: size * 0.49)
    let radius = size * 0.235
    let ringWidth = max(4, size * 0.054)

    let baseArc = NSBezierPath()
    baseArc.appendArc(withCenter: center, radius: radius, startAngle: 36, endAngle: 326)
    baseArc.lineWidth = ringWidth
    baseArc.lineCapStyle = .round
    primaryMint.setStroke()
    baseArc.stroke()

    let highlightArc = NSBezierPath()
    highlightArc.appendArc(withCenter: center, radius: radius, startAngle: 128, endAngle: 214)
    highlightArc.lineWidth = ringWidth
    highlightArc.lineCapStyle = .round
    brightMint.setStroke()
    highlightArc.stroke()

    let endCapSize = size * 0.055
    let endCapRect = NSRect(
        x: size * 0.698,
        y: size * 0.595,
        width: endCapSize,
        height: endCapSize
    )
    primaryMint.setFill()
    NSBezierPath(ovalIn: endCapRect).fill()

    let notchRect = NSRect(
        x: size * 0.395,
        y: size * 0.685,
        width: size * 0.21,
        height: size * 0.058
    )
    let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: notchRect.height / 2, yRadius: notchRect.height / 2)
    accentMint.setFill()
    notchPath.fill()

    let pulsePath = NSBezierPath()
    pulsePath.move(to: NSPoint(x: size * 0.335, y: size * 0.485))
    pulsePath.line(to: NSPoint(x: size * 0.425, y: size * 0.485))
    pulsePath.curve(
        to: NSPoint(x: size * 0.478, y: size * 0.558),
        controlPoint1: NSPoint(x: size * 0.445, y: size * 0.485),
        controlPoint2: NSPoint(x: size * 0.462, y: size * 0.548)
    )
    pulsePath.curve(
        to: NSPoint(x: size * 0.535, y: size * 0.414),
        controlPoint1: NSPoint(x: size * 0.494, y: size * 0.570),
        controlPoint2: NSPoint(x: size * 0.518, y: size * 0.426)
    )
    pulsePath.curve(
        to: NSPoint(x: size * 0.605, y: size * 0.505),
        controlPoint1: NSPoint(x: size * 0.555, y: size * 0.402),
        controlPoint2: NSPoint(x: size * 0.584, y: size * 0.505)
    )
    pulsePath.line(to: NSPoint(x: size * 0.700, y: size * 0.505))
    pulsePath.lineWidth = max(4, size * 0.034)
    pulsePath.lineCapStyle = .round
    pulsePath.lineJoinStyle = .round
    deepMint.setStroke()
    pulsePath.stroke()

    let borderPath = NSBezierPath(roundedRect: cardRect.insetBy(dx: size * 0.006, dy: size * 0.006), xRadius: cornerRadius * 0.96, yRadius: cornerRadius * 0.96)
    borderPath.lineWidth = max(1, size * 0.006)
    brightMint.withAlphaComponent(0.20).setStroke()
    borderPath.stroke()

    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    try data.write(to: url, options: .atomic)
}

let icon = try drawIcon(size: 1024)
try writePNG(icon, to: logoURL)

let renditions: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in renditions {
    let image = try drawIcon(size: size)
    try writePNG(image, to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

print("Generated \(logoURL.path)")
print("Generated \(icnsURL.path)")
