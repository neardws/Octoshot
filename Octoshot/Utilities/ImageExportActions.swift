import AppKit
import OctoshotCore

@MainActor
enum ImageExportActions {
    private static var pending: Task<Void, Never>?

    static func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            do {
                try await operation()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func copy(_ image: NSImage) {
        perform { try await ImageFormats.copyToPasteboardAsync(image) }
    }
}
