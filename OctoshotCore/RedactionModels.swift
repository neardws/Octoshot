import CoreGraphics
import Foundation

public enum RedactionKind: String, Codable, CaseIterable, Identifiable {
    case phone
    case email
    case nationalID
    case creditCard
    case apiKey
    case ipAddress
    case face
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .phone: return "Phone"
        case .email: return "Email"
        case .nationalID: return "ID Number"
        case .creditCard: return "Card"
        case .apiKey: return "API Key"
        case .ipAddress: return "IP"
        case .face: return "Face"
        case .other: return "Sensitive"
        }
    }
}

public struct RedactionCandidate: Identifiable, Equatable {
    public let id: UUID
    /// Region to redact, in the image's points with a top-left origin (the annotation
    /// editor's coordinate space).
    public var rect: CGRect
    public var kind: RedactionKind
    public var detail: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), rect: CGRect, kind: RedactionKind, detail: String, isEnabled: Bool = true) {
        self.id = id
        self.rect = rect
        self.kind = kind
        self.detail = detail
        self.isEnabled = isEnabled
    }
}
