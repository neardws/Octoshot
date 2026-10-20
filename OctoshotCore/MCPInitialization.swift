import Foundation

public enum MCPInitialization {
    public static func result(bundle: Bundle = .main) -> MCPJSONValue {
        .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": .string("octoshot"),
                "version": .string(OctoshotVersion.semanticVersion(bundle: bundle))
            ])
        ])
    }
}
