import Foundation
import LocalAuthentication
import Security

struct KeychainService: Sendable {
    private let service = "app.ciphernotes.touchid-v2"

    var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func saveVaultKey(_ key: Data, for userID: UUID) throws {
        deleteVaultKey(for: userID)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw VaultError.keychain(errSecParam)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: userID),
            kSecAttrAccessControl as String: access,
            kSecValueData as String: key
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    func readVaultKeyAfterBiometrics(for userID: UUID) async throws -> Data {
        let context = LAContext()
        context.localizedReason = "使用 Touch ID 解锁这个本地账户的加密保险柜"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            throw VaultError.biometricsUnavailable
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: userID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecUserCanceled { throw CancellationError() }
            if status == errSecItemNotFound { throw VaultError.touchIDNotConfigured }
            throw VaultError.keychain(status)
        }
        return data
    }

    func deleteVaultKey(for userID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: userID)
        ]
        SecItemDelete(query as CFDictionary)
    }

    func deleteAllVaultKeys() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func account(for userID: UUID) -> String {
        "vault-key-\(userID.uuidString)"
    }
}
