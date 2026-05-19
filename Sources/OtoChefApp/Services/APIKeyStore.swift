import Foundation
import Security

protocol APIKeyStore {
    func saveTranslationAPIKey(_ key: String, for provider: TranslationProvider) throws
    func loadTranslationAPIKey(for provider: TranslationProvider) throws -> String?
    func clearTranslationAPIKey(for provider: TranslationProvider) throws
}

final class MemoryAPIKeyStore: APIKeyStore {
    private var keys: [TranslationProvider: String] = [:]

    func saveTranslationAPIKey(_ key: String, for provider: TranslationProvider) throws {
        keys[provider] = key
    }

    func loadTranslationAPIKey(for provider: TranslationProvider) throws -> String? {
        keys[provider]
    }

    func clearTranslationAPIKey(for provider: TranslationProvider) throws {
        keys.removeValue(forKey: provider)
    }
}

final class KeychainAPIKeyStore: APIKeyStore {
    private let service = "OtoChef"

    func saveTranslationAPIKey(_ key: String, for provider: TranslationProvider) throws {
        let data = Data(key.utf8)
        let query = query(for: provider)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadTranslationAPIKey(for provider: TranslationProvider) throws -> String? {
        var query = query(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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

    func clearTranslationAPIKey(for provider: TranslationProvider) throws {
        let status = SecItemDelete(query(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func query(for provider: TranslationProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "translation-api-key.\(provider.rawValue)"
        ]
    }
}
