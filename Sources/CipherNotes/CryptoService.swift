import CommonCrypto
import CryptoKit
import Foundation
import Security

enum CryptoService {
    static let defaultRounds: UInt32 = 310_000

    static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return data
    }

    static func deriveKey(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let outputCount = 32
        var output = Data(count: outputCount)
        let status = output.withUnsafeMutableBytes { outputBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordData.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                        outputCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.corruptVault }
        return SymmetricKey(data: output)
    }

    static func normalizedUsername(_ username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }

    static func usernameHash(_ username: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(normalizedUsername(username).utf8))
        return Data(SHA256.hash(data: input))
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw VaultError.corruptVault }
        return combined
    }

    static func open(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key)
        } catch {
            throw VaultError.invalidPassword
        }
    }
}
