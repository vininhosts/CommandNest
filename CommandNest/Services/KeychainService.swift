import Foundation
import Security

protocol KeychainServicing {
    func saveAPIKey(_ apiKey: String) throws
    func loadAPIKey() throws -> String?
    func deleteAPIKey() throws
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain returned status \(status)."
        case .invalidData:
            return "The saved API key could not be read."
        }
    }
}

final class KeychainService: KeychainServicing {
    private let service = "com.local.CommandNest.openrouter"
    private let legacyService = "com.local.ShortcutAI.openrouter"
    private let account = "OpenRouterAPIKey"

    func saveAPIKey(_ apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            try deleteAPIKey()
            return
        }

        let data = Data(trimmedKey.utf8)
        let query = baseQuery(service: service)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func loadAPIKey() throws -> String? {
        if let currentKey = try loadAPIKey(service: service) {
            return currentKey
        }

        guard let legacyKey = try loadAPIKey(service: legacyService) else {
            return nil
        }

        try? saveAPIKey(legacyKey)
        return legacyKey
    }

    private func loadAPIKey(service: String) throws -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return key
    }

    func deleteAPIKey() throws {
        for service in [service, legacyService] {
            let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
