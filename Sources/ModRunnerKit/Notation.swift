import Foundation

/// How a note is written down, in OctaMED's notation.
///
/// There were three copies of this — the tracker view, the CLI's `dump` and now
/// the portable skin — and three copies of a table is how two of them end up
/// disagreeing about what B-3 means.
public enum Notation {

    static let noteNames = ["C-", "C#", "D-", "D#", "E-", "F-", "F#",
                            "G-", "G#", "A-", "A#", "B-"]

    /// MED numbers notes from 1, where 1 is C-1.
    public static func name(of note: Int) -> String {
        guard note > 0 else { return "---" }
        let index = note - 1
        return "\(noteNames[index % 12])\(index / 12 + 1)"
    }

    /// The instrument column: two hex digits, or dots where there is nothing.
    public static func instrument(_ number: Int) -> String {
        number > 0 ? String(format: "%02X", number) : ".."
    }

    /// The command column: command and data as four hex digits, or dots.
    public static func command(_ command: Int, _ data: Int) -> String {
        (command != 0 || data != 0) ? String(format: "%02X%02X", command, data) : "...."
    }
}
