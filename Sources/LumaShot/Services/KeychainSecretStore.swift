import Foundation
import Security

protocol SecretStoring {
    func secret(service: String, account: String) throws -> String?
    func setSecret(_ secret: String, service: String, account: String) throws
    func removeSecret(service: String, account: String) throws
}

enum KeychainError: Error, Equatable {
    case emptySecret
    case invalidData
    case unexpectedStatus(OSStatus)
}

struct DeepSeekCredential {
    static let service = "com.lumashot.mac"
    static let account = "deepseek.api-key"

    var store: SecretStoring

    init(store: SecretStoring = KeychainSecretStore()) {
        self.store = store
    }

    func apiKey() throws -> String? {
        guard let stored = try store.secret(service: Self.service, account: Self.account) else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func hasAPIKey() throws -> Bool {
        try apiKey() != nil
    }

    func saveAPIKey(_ value: String) throws {
        try store.setSecret(value, service: Self.service, account: Self.account)
    }

    func removeAPIKey() throws {
        try store.removeSecret(service: Self.service, account: Self.account)
    }
}

/// macOS Keychain item for the DeepSeek API key. The key is never written to UserDefaults, logs, or the capture store.
struct KeychainSecretStore: SecretStoring {
    func secret(service: String, account: String) throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(Self.readQuery(service: service, account: account) as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    func setSecret(_ secret: String, service: String, account: String) throws {
        let query = try Self.addQuery(service: service, account: account, secret: secret)
        SecItemDelete(Self.baseQuery(service: service, account: account) as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func removeSecret(service: String, account: String) throws {
        let status = SecItemDelete(Self.baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func normalizedSecret(_ secret: String) throws -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptySecret }
        return trimmed
    }

    static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func readQuery(service: String, account: String) -> [String: Any] {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func addQuery(service: String, account: String, secret: String) throws -> [String: Any] {
        let normalized = try normalizedSecret(secret)
        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = Data(normalized.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }
}
