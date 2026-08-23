import Foundation

/// Argument parsing by hand.
///
/// The project has no third-party dependencies and this is not the place to
/// acquire the first one: four subcommands and half a dozen options do not need
/// a parsing library.
struct Arguments {

    let command: String
    /// Everything that is not an option: file names, mostly.
    private(set) var operands: [String] = []
    private var options: [String: String] = [:]
    private var flags: Set<String> = []

    enum ParseError: LocalizedError {
        case missingCommand
        case unknownCommand(String)
        case missingValue(String)

        var errorDescription: String? {
            switch self {
            case .missingCommand:
                return "no command given"
            case .unknownCommand(let name):
                return "unknown command '\(name)'"
            case .missingValue(let name):
                return "'\(name)' needs a value"
            }
        }
    }

    /// Options that take a value; anything else beginning with a dash is a flag.
    private static let valueOptions: Set<String> = [
        "-o", "--output", "--seconds", "--rate", "--block",
        "--layout", "--visualiser", "--visualizer", "--width", "--height", "--pointer"
    ]

    init(_ arguments: [String], commands: Set<String>) throws {
        var rest = arguments
        guard let command = rest.first else { throw ParseError.missingCommand }
        guard commands.contains(command) else { throw ParseError.unknownCommand(command) }
        self.command = command
        rest.removeFirst()

        var index = 0
        while index < rest.count {
            let argument = rest[index]
            // A bare "-" is a file name meaning stdout, not an option.
            if argument.hasPrefix("-"), argument != "-" {
                if Self.valueOptions.contains(argument) {
                    guard index + 1 < rest.count else { throw ParseError.missingValue(argument) }
                    options[argument] = rest[index + 1]
                    index += 2
                    continue
                }
                flags.insert(argument)
            } else {
                operands.append(argument)
            }
            index += 1
        }
    }

    func string(_ names: String...) -> String? {
        names.compactMap { options[$0] }.first
    }

    func int(_ names: String...) -> Int? {
        names.compactMap { options[$0] }.first.flatMap(Int.init)
    }

    func double(_ names: String...) -> Double? {
        names.compactMap { options[$0] }.first.flatMap(Double.init)
    }

    func has(_ names: String...) -> Bool {
        names.contains { flags.contains($0) }
    }
}
