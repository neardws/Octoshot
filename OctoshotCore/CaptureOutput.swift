import Foundation
import CoreGraphics

public enum CaptureOutput {
    public static func filename(_ name: String, format: ScreenshotFormat) -> String {
        let url = URL(fileURLWithPath: name)
        let known = ["png", "jpg", "jpeg", "heic"]
        let stem = known.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : name
        return stem + "." + format.fileExtension
    }

    public static func explicitURL(_ url: URL, format: ScreenshotFormat) -> URL {
        url.pathExtension.isEmpty ? url.appendingPathExtension(format.fileExtension) : url
    }

    public static func writeUnique(_ data: Data, to proposedURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: proposedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var number = 1
        while true {
            let url = number == 1 ? proposedURL : proposedURL.deletingLastPathComponent()
                .appendingPathComponent("\(proposedURL.deletingPathExtension().lastPathComponent) (\(number)).\(proposedURL.pathExtension)")
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                number += 1
            }
        }
    }
}

public enum CaptureDisplaySelection {
    public static func validate(_ requested: UInt32?, available: [UInt32]) throws {
        guard let requested else { return }
        guard available.contains(requested) else {
            let identifiers = available.isEmpty ? "(none)" : available.sorted().map(String.init).joined(separator: ", ")
            throw CaptureError.captureFailed("Unknown display id \(requested). Available display ids: \(identifiers)")
        }
    }

    public static func validateActive(_ requested: UInt32?) throws {
        guard requested != nil else { return }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { throw CaptureError.noDisplays }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { throw CaptureError.noDisplays }
        try validate(requested, available: Array(ids.prefix(Int(count))))
    }
}

public enum CSVEncoder {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                field.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\r\n")
    }
}
