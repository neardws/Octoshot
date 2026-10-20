import Foundation

public enum CaptureArgumentParser {
    public static func parse(_ args: [String]) throws -> AgentCaptureOptions {
        var options = AgentCaptureOptions(mode: .fullscreen)
        var index = 0

        func nextValue(for option: String) throws -> String {
            guard index + 1 < args.count else {
                throw ArgumentError.missingValue(option)
            }
            index += 1
            return args[index]
        }

        while index < args.count {
            let option = args[index]
            switch option {
            case "--mode":
                guard let mode = AgentCaptureMode(rawValue: try nextValue(for: option)) else {
                    throw ArgumentError.invalidValue(option, "expected fullscreen, display, window or region")
                }
                options.mode = mode
            case "--display-id", "--window-id":
                let value = try nextValue(for: option)
                guard let identifier = UInt32(value) else {
                    throw ArgumentError.invalidValue(option, "expected an unsigned 32-bit integer")
                }
                if option == "--display-id" {
                    options.displayID = identifier
                } else {
                    options.windowID = identifier
                }
            case "--rect":
                let value = try nextValue(for: option)
                let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                let coordinates = parts.compactMap { Double($0) }
                guard parts.count == 4, coordinates.count == 4, coordinates.allSatisfy({ $0.isFinite }) else {
                    throw ArgumentError.invalidValue(option, "expected four finite numbers: x,y,w,h")
                }
                options.region = CGRect(
                    x: coordinates[0], y: coordinates[1],
                    width: coordinates[2], height: coordinates[3]
                )
            case "--output":
                options.outputPath = URL(fileURLWithPath: try nextValue(for: option))
            case "--base64":
                options.includeBase64 = true
            default:
                throw ArgumentError.invalidValue(option, "unknown capture option")
            }
            index += 1
        }
        return options
    }

    private enum ArgumentError: LocalizedError {
        case missingValue(String)
        case invalidValue(String, String)

        var errorDescription: String? {
            switch self {
            case .missingValue(let option):
                return "Missing value for \(option)"
            case .invalidValue(let option, let requirement):
                return "Invalid value for \(option): \(requirement)"
            }
        }
    }
}
