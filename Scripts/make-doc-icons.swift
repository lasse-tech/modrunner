#!/usr/bin/env swift
//
// Draws the Finder icons for the file types ModRunner opens and packs them into
// .icns files.
//
//   swift Scripts/make-doc-icons.swift [output-directory]
//
// A light document with a folded corner, so a module reads as a file rather
// than as a second copy of the app icon; the Fibonacci bars sit at the foot as
// a solid silhouette, with the extension above them. Below 32 points the text
// goes: at that size it is three grey pixels, and the bars alone still say what
// the file is.

import AppKit
import Foundation

// MARK: - Palette (brand/README.txt)

let orange = NSColor(srgbRed: 0xFF / 255, green: 0x6B / 255, blue: 0x35 / 255, alpha: 1)
let salmon = NSColor(srgbRed: 0xFF / 255, green: 0xA9 / 255, blue: 0x97 / 255, alpha: 1)
let blue   = NSColor(srgbRed: 0x3B / 255, green: 0x67 / 255, blue: 0xA2 / 255, alpha: 1)
let dark   = NSColor(srgbRed: 0x17 / 255, green: 0x13 / 255, blue: 0x0F / 255, alpha: 1)
let paper  = NSColor(srgbRed: 0xED / 255, green: 0xE6 / 255, blue: 0xE0 / 255, alpha: 1)
let edge   = NSColor(srgbRed: 0xCB / 255, green: 0xC1 / 255, blue: 0xB8 / 255, alpha: 1)
let fold   = NSColor(srgbRed: 0xD8 / 255, green: 0xCF / 255, blue: 0xC7 / 255, alpha: 1)

/// Six bars, heights 1 : 2 : 3 : 5 : 8 : 13, coloured in three pairs.
let fibonacci = [1, 2, 3, 5, 8, 13]
let barColours = [blue, blue, salmon, salmon, orange, orange]

// MARK: - Drawing

func drawIcon(extension name: String, size: CGFloat, compact: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setShouldAntialias(true)

    // The page. Portrait, centred, with room for the shadow at the edges.
    let pageWidth = size * 0.68
    let pageHeight = size * 0.84
    let origin = CGPoint(x: (size - pageWidth) / 2, y: (size - pageHeight) / 2)
    let corner = size * 0.06          // the folded corner, top right
    let radius = size * 0.045

    let page = CGMutablePath()
    let minX = origin.x, minY = origin.y
    let maxX = origin.x + pageWidth, maxY = origin.y + pageHeight

    page.move(to: CGPoint(x: minX + radius, y: minY))
    page.addLine(to: CGPoint(x: maxX - radius, y: minY))
    page.addQuadCurve(to: CGPoint(x: maxX, y: minY + radius), control: CGPoint(x: maxX, y: minY))
    page.addLine(to: CGPoint(x: maxX, y: maxY - corner))
    page.addLine(to: CGPoint(x: maxX - corner, y: maxY))
    page.addLine(to: CGPoint(x: minX + radius, y: maxY))
    page.addQuadCurve(to: CGPoint(x: minX, y: maxY - radius), control: CGPoint(x: minX, y: maxY))
    page.addLine(to: CGPoint(x: minX, y: minY + radius))
    page.addQuadCurve(to: CGPoint(x: minX + radius, y: minY), control: CGPoint(x: minX, y: minY))
    page.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.03,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.addPath(page)
    context.setFillColor(paper.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(page)
    context.setStrokeColor(edge.cgColor)
    context.setLineWidth(max(1, size * 0.006))
    context.strokePath()

    // The turned-back flap.
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: maxX - corner, y: maxY))
    flap.addLine(to: CGPoint(x: maxX - corner, y: maxY - corner))
    flap.addLine(to: CGPoint(x: maxX, y: maxY - corner))
    flap.closeSubpath()
    context.addPath(flap)
    context.setFillColor(fold.cgColor)
    context.fillPath()
    context.addPath(flap)
    context.setStrokeColor(edge.cgColor)
    context.strokePath()

    // The bars, as a solid silhouette standing on the foot of the page.
    let inset = pageWidth * 0.14
    let barsWidth = pageWidth - inset * 2
    let gap = barsWidth * 0.055
    let barWidth = (barsWidth - gap * 5) / 6
    let tallest = pageHeight * (compact ? 0.52 : 0.40)
    let baseline = minY + pageHeight * (compact ? 0.24 : 0.16)

    for (index, steps) in fibonacci.enumerated() {
        let height = tallest * CGFloat(steps) / CGFloat(fibonacci.last!)
        let rect = CGRect(x: minX + inset + (barWidth + gap) * CGFloat(index),
                          y: baseline,
                          width: barWidth,
                          height: max(height, size * 0.012))
        let path = CGPath(roundedRect: rect,
                          cornerWidth: min(barWidth / 2, size * 0.008),
                          cornerHeight: min(barWidth / 2, size * 0.008),
                          transform: nil)
        context.addPath(path)
        context.setFillColor(barColours[index].cgColor)
        context.fillPath()
    }

    // The extension, above the bars. Dropped on the small sizes.
    if !compact {
        let text = name as NSString
        let fontSize = pageWidth * 0.22
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dark,
            .kern: -fontSize * 0.02,
        ]
        let measured = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: minX + (pageWidth - measured.width) / 2,
                              y: baseline + tallest + pageHeight * 0.07),
                  withAttributes: attributes)
    }

    return image
}

// MARK: - Writing

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

/// The sizes an .icns carries, and the @2x variants beside them.
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("brand/macos")

for (name, file) in [(".med", "ModRunnerDocMED"), (".mod", "ModRunnerDocMOD")] {
    let iconset = outputDirectory.appendingPathComponent("\(file).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for (points, scale) in sizes {
        let pixels = points * scale
        // The extension is unreadable below about 32 points, and a smear of
        // grey pixels is worse than no text at all.
        let image = drawIcon(extension: name, size: CGFloat(pixels), compact: points < 32)
        guard let data = png(image, pixels: pixels) else { continue }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path]
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        try? FileManager.default.removeItem(at: iconset)
        print("wrote \(file).icns")
    } else {
        print("iconutil failed for \(file)")
        exit(1)
    }
}
