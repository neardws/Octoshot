import CryptoKit
import Foundation
import Security

public protocol DiaryKeyProvider {
    func key() throws -> SymmetricKey
}

public struct InMemoryDiaryKeyProvider: DiaryKeyProvider {
    private let storedKey: SymmetricKey
    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) { storedKey = key }
    public func key() -> SymmetricKey { storedKey }
}

public enum DiaryKeyError: Error {
    case keychain(OSStatus)
    case invalidKey
}

public final class KeychainDiaryKeyProvider: DiaryKeyProvider {
    public init() {}

    public func key() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.neardws.Octoshot.diary",
            kSecAttrAccount as String: "payload-key-v1",
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        if let existing = try read(query) { return existing }
        let generated = SymmetricKey(size: .bits256)
        var insertion = query
        insertion.removeValue(forKey: kSecUseAuthenticationUI as String)
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insertion[kSecValueData as String] = generated.withUnsafeBytes { Data($0) }
        let status = SecItemAdd(insertion as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try read(query) { return existing }
        guard status == errSecSuccess else { throw DiaryKeyError.keychain(status) }
        return generated
    }

    private func read(_ query: [String: Any]) throws -> SymmetricKey? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DiaryKeyError.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw DiaryKeyError.invalidKey }
        return SymmetricKey(data: data)
    }
}
