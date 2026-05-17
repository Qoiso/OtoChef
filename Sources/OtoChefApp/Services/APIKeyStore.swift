import Foundation
import Security

protocol APIKeyStore {
    func saveTranslationAPIKey(_ key: String) throws
    func loadTranslationAPIKey() throws -> String?
}

final class MemoryAPIKeyStore: APIKeyStore {
    private var key: String?

    func saveTranslationAPIKey(_ key: String) throws {
        self.key = key
    }

    func loadTranslationAPIKey() throws -> String? {
        key
    }
}

final class KeychainAPIKeyStore: APIKeyStore {
    private let service = "OtoChef"
    private let account = "translation-api-key"

    func saveTranslationAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadTranslationAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

