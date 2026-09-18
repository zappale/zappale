import Foundation
import Security

/// API key 的唯一存放处：登录 Keychain。
/// key 按账户名寻址，连接信息（endpoint/model）存 UserDefaults，二者永不混存。
public struct KeychainStore {
    public let service: String
    /// 旧版本 service（QuickAgent 时代）；读取时兜底迁移。
    public var legacyService: String? = nil

    public init(service: String, legacyService: String? = nil) {
        self.service = service
        self.legacyService = legacyService
    }

    public enum KeychainError: LocalizedError {
        case unhandled(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return "Keychain 操作失败（OSStatus \(status)）"
            }
        }
    }

    public func set(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandled(updateStatus)
        }
    }

    public func get(account: String) -> String? {
        if let value = rawGet(service: service, account: account) { return value }
        // 从旧 service（QuickAgent 时代）迁移：读到就写入新 service
        if let legacyService, let legacy = rawGet(service: legacyService, account: account) {
            try? set(legacy, account: account)
            return legacy
        }
        return nil
    }

    private func rawGet(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
