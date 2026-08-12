import Foundation

/// A rectangle in pixels, top-left origin — the way a framebuffer is indexed
/// rather than the way a coordinate system is argued about.
public struct Rect: Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public func inset(by amount: Int) -> Rect {
        Rect(x + amount, y + amount,
             Swift.max(0, width - amount * 2), Swift.max(0, height - amount * 2))
    }
}

/// A colour as the framebuffer stores it: red, green, blue, alpha, one byte
/// each, in that order, which is also the order PNG wants them in.
public struct Colour: Equatable {
    public var rgba: UInt32

    public init(rgba: UInt32) { self.rgba = rgba }

    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) {
        rgba = UInt32(red) << 24 | UInt32(green) << 16 | UInt32(blue) << 8 | UInt32(alpha)
    }

    public var red: UInt8 { UInt8((rgba >> 24) & 0xFF) }
    public var green: UInt8 { UInt8((rgba >> 16) & 0xFF) }
    public var blue: UInt8 { UInt8((rgba >> 8) & 0xFF) }
    public var alpha: UInt8 { UInt8(rgba & 0xFF) }
}

/// A software framebuffer, and every drawing operation the Workbench skin needs.
///
/// There is no toolkit under this and no window: the whole interface is painted
/// into an array of pixels, which is what makes it the same picture on every
/// platform and testable without a display at all. What eventually puts those
/// pixels on a screen is somebody else's problem — deliberately, because that
/// is the part that differs between X11, Win32 and everything else.
///
/// Every operation clips. Drawing outside the canvas is a normal thing for a
/// scrolling tracker to attempt, not a programming error worth trapping on.
public struct Canvas {

    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt32]

    public init(width: Int, height: Int, fill: Colour = Colour(0, 0, 0)) {
        self.width = Swift.max(0, width)
        self.height = Swift.max(0, height)
        self.pixels = [UInt32](repeating: fill.rgba, count: self.width * self.height)
    }

    // MARK: - Primitives

    public mutating func set(_ x: Int, _ y: Int, _ colour: Colour) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = colour.rgba
    }

    public func pixel(_ x: Int, _ y: Int) -> Colour {
        guard x >= 0, y >= 0, x < width, y < height else { return Colour(0, 0, 0, 0) }
        return Colour(rgba: pixels[y * width + x])
    }

    public mutating func fill(_ rect: Rect, _ colour: Colour) {
        let x0 = Swift.max(0, rect.x), x1 = Swift.min(width, rect.maxX)
        let y0 = Swift.max(0, rect.y), y1 = Swift.min(height, rect.maxY)
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            let row = y * width
            for x in x0..<x1 { pixels[row + x] = colour.rgba }
        }
    }

    public mutating func fillAll(_ colour: Colour) {
        fill(Rect(0, 0, width, height), colour)
    }

    /// A one-pixel outline, drawn inside the rectangle.
    public mutating func frame(_ rect: Rect, _ colour: Colour, width lineWidth: Int = 1) {
        fill(Rect(rect.x, rect.y, rect.width, lineWidth), colour)
        fill(Rect(rect.x, rect.maxY - lineWidth, rect.width, lineWidth), colour)
        fill(Rect(rect.x, rect.y, lineWidth, rect.height), colour)
        fill(Rect(rect.maxX - lineWidth, rect.y, lineWidth, rect.height), colour)
    }
}
