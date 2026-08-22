#!/usr/bin/env swift
//
// Packs the brand artwork into Windows .ico files.
//
//   swift Scripts/make-windows-icons.swift [output-directory]
//
// The artwork already exists: brand/macos holds the app icon as an .iconset of
// PNGs, and the two document icons as .icns, which since Mountain Lion is a
// container with PNGs inside it. An .ico is a third container around the same
// pictures, so nothing is drawn here and nothing is resampled -- this only
// repacks, which is why it needs no image library and runs anywhere Swift does.
//
// Companion to make-doc-icons.swift, which draws the document icons in the
// first place and needs AppKit for it. This one deliberately does not.

import Foundation

// MARK: - PNG

/// Width and height out of the IHDR chunk, which is always first.
func pngSize(_ data: Data) -> (width: Int, height: Int)? {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard data.count > 24, Array(data.prefix(8)) == signature else { return nil }
    func be32(_ offset: Int) -> Int {
        let bytes = data[data.startIndex + offset ..< data.startIndex + offset + 4]
        return bytes.reduce(0) { $0 << 8 | Int($1) }
    }
    guard be32(12) == 0x49484452 else { return nil }   // "IHDR"
    return (be32(16), be32(20))
}

// MARK: - ICNS

/// The PNGs inside an .icns, in the order the container lists them.
///
/// The older `ic04` and `ic05` entries are raw ARGB rather than PNG and are
/// left behind: they are the 16 and 32 point sizes, and the retina entries
/// cover the same pictures at twice the resolution.
func icnsPNGs(_ data: Data) -> [Data] {
    guard data.count > 8, Array(data.prefix(4)) == Array("icns".utf8) else { return [] }
    var found: [Data] = []
    var offset = 8
    while offset + 8 <= data.count {
        let header = data[data.startIndex + offset ..< data.startIndex + offset + 8]
        let length = header.dropFirst(4).reduce(0) { $0 << 8 | Int($1) }
        guard length >= 8, offset + length <= data.count else { break }
        let payload = Data(data[data.startIndex + offset + 8 ..< data.startIndex + offset + length])
        if pngSize(payload) != nil { found.append(payload) }
        offset += length
    }
    return found
}

// MARK: - ICO

/// The sizes Windows asks for. 48 is the one the artwork has no source for --
/// the iconset doubles from 16 and never lands on it -- so Explorer's large
/// icon view scales down from 64. Everything else is packed at its own size.
let wanted = [16, 32, 48, 64, 128, 256]

/// An .ico around PNGs, which Windows has taken at every size since Vista.
func ico(from images: [Data]) -> Data {
    // Keyed by size on the way in: an .icns lists some pictures twice, once as
    // a retina entry and once as a plain one -- ic13 and ic08 are both 256 --
    // and two entries of the same size in an .ico is at best wasted space.
    var bySize: [Int: Data] = [:]
    for image in images {
        guard let size = pngSize(image), size.width == size.height,
              wanted.contains(size.width) else { continue }
        if bySize[size.width] == nil { bySize[size.width] = image }
    }
    let entries = bySize.map { (size: $0.key, data: $0.value) }.sorted { $0.size < $1.size }

    var out = Data()
    func append16(_ value: Int) { out.append(UInt8(value & 0xFF)); out.append(UInt8(value >> 8 & 0xFF)) }
    func append32(_ value: Int) {
        for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8(value >> shift & 0xFF)) }
    }

    append16(0)                 // reserved
    append16(1)                 // 1 = icon
    append16(entries.count)

    var offset = 6 + entries.count * 16
    for entry in entries {
        // 256 does not fit in a byte and is written as zero, which is the
        // convention rather than a trick.
        out.append(UInt8(entry.size == 256 ? 0 : entry.size))
        out.append(UInt8(entry.size == 256 ? 0 : entry.size))
        out.append(0)           // palette size, 0 for truecolour
        out.append(0)           // reserved
        append16(1)             // colour planes
        append16(32)            // bits per pixel
        append32(entry.data.count)
        append32(offset)
        offset += entry.data.count
    }
    for entry in entries { out.append(entry.data) }
    return out
}

// MARK: - Running it

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("brand")
let output = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1])
    : brand.appendingPathComponent("windows")

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func write(_ data: Data, named name: String, from source: String, sizes: [Int]) throws {
    let url = output.appendingPathComponent(name)
    try data.write(to: url)
    let list = sizes.map(String.init).joined(separator: ", ")
    print("\(name)  \(data.count) bytes  \(sizes.count) sizes (\(list))  <- \(source)")
}

func sizesIn(_ images: [Data]) -> [Int] {
    Array(Set(images.compactMap { pngSize($0)?.width }.filter { wanted.contains($0) })).sorted()
}

// The app icon, from the iconset. Several files decode to the same pixel size
// (icon_16x16-2x.png is 32x32, and so is icon_32x32.png), so they are keyed by
// size and the duplicates fall away.
let iconset = brand.appendingPathComponent("macos/ModRunner.iconset")
var appImages: [Int: Data] = [:]
for file in try FileManager.default.contentsOfDirectory(at: iconset, includingPropertiesForKeys: nil)
where file.pathExtension.lowercased() == "png" {
    let data = try Data(contentsOf: file)
    if let size = pngSize(data), size.width == size.height { appImages[size.width] = data }
}
let app = Array(appImages.values)
try write(ico(from: app), named: "ModRunner.ico",
          from: "ModRunner.iconset", sizes: sizesIn(app))

// The document icons, unpacked from their .icns.
for (icns, name) in [("ModRunnerDocMED", "ModRunnerDocMED.ico"),
                     ("ModRunnerDocMOD", "ModRunnerDocMOD.ico")] {
    let source = brand.appendingPathComponent("macos/\(icns).icns")
    guard FileManager.default.fileExists(atPath: source.path) else {
        print("skipping \(name): \(source.lastPathComponent) is not there")
        continue
    }
    let images = icnsPNGs(try Data(contentsOf: source))
    try write(ico(from: images), named: name, from: "\(icns).icns", sizes: sizesIn(images))
}
