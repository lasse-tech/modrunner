import Foundation

/// Minimal 16-bit stereo WAV writer.
///
/// Lives here rather than in the test target because rendering to a file is
/// something the command line does too, and a second copy of a header layout is
/// a second place to get it wrong.
public enum WAVWriter {

    /// The 44-byte canonical header followed by interleaved 16-bit frames.
    public static func data(left: [Float], right: [Float], sampleRate: Int) -> Data {
        precondition(left.count == right.count)
        let frames = left.count
        let byteRate = sampleRate * 2 * 2
        let dataSize = frames * 2 * 2

        var out = Data()
        out.reserveCapacity(44 + dataSize)

        func ascii(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func le32(_ v: Int) { for i in 0..<4 { out.append(UInt8((v >> (8 * i)) & 0xFF)) } }
        func le16(_ v: Int) { for i in 0..<2 { out.append(UInt8((v >> (8 * i)) & 0xFF)) } }

        ascii("RIFF"); le32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); le32(16); le16(1); le16(2)
        le32(sampleRate); le32(byteRate); le16(4); le16(16)
        ascii("data"); le32(dataSize)

        for i in 0..<frames {
            for value in [left[i], right[i]] {
                let clamped = max(-1.0, min(1.0, value))
                le16(Int(Int16(clamped * 32767)))
            }
        }
        return out
    }

    public static func write(left: [Float], right: [Float], sampleRate: Int, to url: URL) throws {
        try data(left: left, right: right, sampleRate: sampleRate).write(to: url)
    }
}
