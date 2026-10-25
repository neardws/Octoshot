import Foundation

func encodeMCPFileResult(_ result: [String: String]) throws -> String {
    String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
}
