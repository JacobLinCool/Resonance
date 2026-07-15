#!/usr/bin/env swift
import AppKit

// Renders Resonance's app icon: white sound-resonance arcs radiating from a
// center point over a deep indigo→blue gradient squircle. Drawn with Core
// Graphics paths so it renders identically headless (no GUI dependency).
//
// Usage: swift GenerateAppIcon.swift <output-dir>

func drawResonanceMark(in graphics: CGContext, size: CGFloat) {
    let center = CGPoint(x: size / 2, y: size / 2)
    graphics.setLineCap(.round)

    graphics.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let dot = size * 0.05
    graphics.addEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
    graphics.fillPath()

    let radii: [CGFloat] = [0.15, 0.235, 0.32]
    let alphas: [CGFloat] = [1.0, 0.8, 0.55]
    let degreesToRadians = CGFloat.pi / 180
    graphics.setLineWidth(size * 0.032)
    for (index, radiusFraction) in radii.enumerated() {
        graphics.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alphas[index]))
        graphics.addArc(
            center: center, radius: size * radiusFraction,
            startAngle: -48 * degreesToRadians, endAngle: 48 * degreesToRadians, clockwise: false)
        graphics.strokePath()
        graphics.addArc(
            center: center, radius: size * radiusFraction,
            startAngle: 132 * degreesToRadians, endAngle: 228 * degreesToRadians, clockwise: false)
        graphics.strokePath()
    }
}

func renderIcon(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let graphics = context.cgContext
    graphics.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Rounded-rect background with the macOS content inset, indigo→blue gradient.
    let inset = size * 0.09
    let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
    let radius = rect.width * 0.2237
    graphics.saveGState()
    graphics.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    graphics.clip()
    let colors =
        [
            CGColor(red: 0.20, green: 0.13, blue: 0.52, alpha: 1),  // deep indigo
            CGColor(red: 0.22, green: 0.48, blue: 0.95, alpha: 1),  // bright blue
        ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        graphics.drawLinearGradient(
            gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    }
    graphics.restoreGState()

    // Center dot and symmetric wave arcs, fading as they radiate outward.
    drawResonanceMark(in: graphics, size: size)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for pixelSize in [16, 32, 64, 128, 256, 512, 1024] {
    guard let data = renderIcon(pixels: pixelSize) else {
        writeError("failed to render \(pixelSize)px\n")
        exit(1)
    }
    let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("icon_\(pixelSize).png")
    do { try data.write(to: outputURL); print("wrote \(outputURL.lastPathComponent)") } catch {
        writeError("write \(pixelSize) failed: \(error)\n"); exit(1)
    }
}
