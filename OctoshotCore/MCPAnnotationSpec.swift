import Foundation

public func decodeAgentAnnotationSpec(from value: MCPJSONValue) throws -> AgentAnnotationSpec {
    guard case .object = value else {
        throw CaptureError.captureFailed("spec must be an object")
    }
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(AgentAnnotationSpec.self, from: data)
}
