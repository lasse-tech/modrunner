import Foundation

/// Writes a canvas out as a PNG, with no library under it.
///
/// PNG's compression is deflate, and deflate is allowed to not compress: a
/// stored block is a length, its complement, and the bytes. That is what this
/// does, which keeps the encoder to a page of arithmetic and needs no zlib on
/// any of the three platforms.
///
/// The cost is real and worth knowing before you commit the output anywhere: a
/// flat-coloured interface is the best case for a compressor and the worst case
/// for this, so a 560×632 window comes out around 1.4 MB where a proper encoder
/// writes 9 KB — a factor of 150. Every viewer opens these files, and anything
/// being kept rather than looked at once should be run through a real encoder
/// afterwards.
public enum PNG {

    public static func encode(_ canvas: Canvas) -> Data {
        var raw = Data()
        raw.reserveCapacity(canvas.height * (canvas.width * 4 + 1))
        for y in 0..<canvas.height {
            raw.append(0)  // filter: none
            for x in 0..<canvas.width {
                let rgba = canvas.pixels[y * canvas.width + x]
                raw.append(UInt8((rgba >> 24) & 0xFF))
                raw.append(UInt8((rgba >> 16) & 0xFF))
                raw.append(UInt8((rgba >> 8) & 0xFF))
                raw.append(UInt8(rgba & 0xFF))
            }
        }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var header = Data()
        header.append(be32(UInt32(canvas.width)))
        header.append(be32(UInt32(canvas.height)))
        header.append(contentsOf: [8, 6, 0, 0, 0])  // 8 bits, RGBA, deflate, no filter, no interlace
        png.append(chunk("IHDR", header))
        png.append(chunk("IDAT", zlibStored(raw)))
        png.append(chunk("IEND", Data()))
        return png
    }

    public static func write(_ canvas: Canvas, to url: URL) throws {
        try encode(canvas).write(to: url)
    }

    // MARK: - Containers

    private static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
              UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    private static func chunk(_ type: String, _ payload: Data) -> Data {
        var out = be32(UInt32(payload.count))
        let body = Data(type.utf8) + payload
        out.append(body)
        out.append(be32(crc32(body)))
        return out
    }

    /// A zlib stream whose deflate blocks are all stored.
    private static func zlibStored(_ input: Data) -> Data {
        var out = Data([0x78, 0x01])  // deflate, 32K window, no dictionary, fastest
        var index = 0
        let maximum = 65_535
        repeat {
            let count = Swift.min(maximum, input.count - index)
            let last: UInt8 = (index + count >= input.count) ? 1 : 0
            out.append(last)
            out.append(UInt8(count & 0xFF))
            out.append(UInt8((count >> 8) & 0xFF))
            out.append(UInt8(~count & 0xFF))
            out.append(UInt8((~count >> 8) & 0xFF))
            out.append(input.subdata(in: index..<(index + count)))
            index += count
        } while index < input.count
        out.append(be32(adler32(input)))
        return out
    }

    // MARK: - Checksums

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data {
            value = crcTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
        }
        return value ^ 0xFFFF_FFFF
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
    }
}
