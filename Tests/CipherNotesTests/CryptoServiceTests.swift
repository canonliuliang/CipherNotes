import CryptoKit
import XCTest
@testable import CipherNotes

final class CryptoServiceTests: XCTestCase {
    func testEncryptionRoundTrip() throws {
        let key = SymmetricKey(data: try CryptoService.randomData(count: 32))
        let plaintext = Data("绝密内容".utf8)
        let ciphertext = try CryptoService.seal(plaintext, using: key)
        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(try CryptoService.open(ciphertext, using: key), plaintext)
    }

    func testWrongKeyCannotDecrypt() throws {
        let first = SymmetricKey(data: try CryptoService.randomData(count: 32))
        let second = SymmetricKey(data: try CryptoService.randomData(count: 32))
        let ciphertext = try CryptoService.seal(Data("secret".utf8), using: first)
        XCTAssertThrowsError(try CryptoService.open(ciphertext, using: second))
    }

    func testPasswordDerivationIsStable() throws {
        let salt = Data(repeating: 7, count: 16)
        let first = try CryptoService.deriveKey(password: "correct horse battery staple", salt: salt, rounds: 1_000)
        let second = try CryptoService.deriveKey(password: "correct horse battery staple", salt: salt, rounds: 1_000)
        XCTAssertEqual(first.withUnsafeBytes { Data($0) }, second.withUnsafeBytes { Data($0) })
    }

    func testVaultPersistsOnlyCiphertextAndCanRelock() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            let username = "private-user"
            let password = "a-local-user-password"
            XCTAssertEqual(store.state, .needsAdminSetup)
            store.registerUser(username: username, password: password, confirmation: password)
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.userCount, 1)

            let id = store.addNote()
            store.updateNote(id: id, title: "银行卡密码提示", body: "只有我知道的紫色长颈鹿")
            let diskBytes = try Data(contentsOf: url)
            let diskText = String(decoding: diskBytes, as: UTF8.self)
            XCTAssertFalse(diskText.contains("银行卡密码提示"))
            XCTAssertFalse(diskText.contains("紫色长颈鹿"))
            XCTAssertTrue(diskText.contains(username))
            XCTAssertEqual(store.accounts.map(\.displayName), [username])

            store.lock()
            XCTAssertEqual(store.state, .locked)
            XCTAssertTrue(store.notes.isEmpty)
            store.unlock(username: "somebody-else", password: password)
            XCTAssertEqual(store.state, .locked)
            store.unlock(username: username, password: "wrong-password")
            XCTAssertEqual(store.state, .locked)
            store.unlock(username: username, password: password)
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.notes.first?.body, "只有我知道的紫色长颈鹿")
            XCTAssertEqual(store.signedInUsername, username)
        }
    }

    func testUsersHaveSeparateEncryptedNotes() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)

            store.registerUser(username: "alice", password: "alice-password-123", confirmation: "alice-password-123")
            let aliceID = store.addNote()
            store.updateNote(id: aliceID, title: "Alice", body: "Alice 的私密内容")
            store.lock()

            store.registerUser(username: "bob", password: "bob-password-12345", confirmation: "bob-password-12345")
            let bobID = store.addNote()
            store.updateNote(id: bobID, title: "Bob", body: "Bob 的私密内容")
            XCTAssertEqual(store.notes.count, 1)
            XCTAssertEqual(store.notes.first?.title, "Bob")
            store.lock()

            guard let aliceAccount = store.accounts.first(where: { $0.displayName == "alice" }) else {
                return XCTFail("应该显示 alice 账户")
            }
            store.unlock(userID: aliceAccount.id, password: "alice-password-123")
            XCTAssertEqual(store.notes.count, 1)
            XCTAssertEqual(store.notes.first?.title, "Alice")

            let diskText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            XCTAssertFalse(diskText.contains("Alice 的私密内容"))
            XCTAssertFalse(diskText.contains("Bob 的私密内容"))
            XCTAssertTrue(diskText.contains("alice"))
            XCTAssertTrue(diskText.contains("bob"))
            XCTAssertEqual(store.accounts.map(\.displayName), ["alice", "bob"])
        }
    }

    func testRecoveryCodeResetsUserPasswordAndPreservesNotes() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let oldPassword = "old-user-password"
            let newPassword = "new-user-password"
            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "recover-me", password: oldPassword, confirmation: oldPassword)
            guard let recoveryCode = store.recoveryCodeToShow else {
                return XCTFail("注册后应该显示恢复码")
            }
            XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(recoveryCode))
            store.dismissRecoveryCode()

            let id = store.addNote()
            store.updateNote(id: id, title: "恢复测试", body: "密码重置后仍然存在")
            store.lock()

            store.resetPasswordWithRecoveryCode(username: "recover-me", recoveryCode: recoveryCode.lowercased(), newPassword: newPassword, confirmation: newPassword)
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.notes.first?.body, "密码重置后仍然存在")
            guard let newRecoveryCode = store.recoveryCodeToShow else {
                return XCTFail("重设密码后应该显示新的恢复码")
            }
            XCTAssertNotEqual(recoveryCode, newRecoveryCode)

            store.lock()
            store.unlock(username: "recover-me", password: oldPassword)
            XCTAssertEqual(store.state, .locked)
            store.unlock(username: "recover-me", password: newPassword)
            XCTAssertEqual(store.state, .unlocked)
        }
    }

    func testEmptyUsernamesAndPasswordsAreAllowed() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "", password: "", confirmation: "")
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.signedInUsername, "未命名账户")
            XCTAssertEqual(store.accounts.map(\.displayName), ["未命名账户"])
            store.lock()
            store.unlock(username: "", password: "")
            XCTAssertEqual(store.state, .unlocked)
        }
    }

    func testOnlyCurrentUserCanDeleteTheirOwnAccount() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "alice", password: "alice-pass", confirmation: "alice-pass")
            let aliceID = store.addNote()
            store.updateNote(id: aliceID, title: "Alice 数据", body: "只属于 Alice")
            store.lock()

            store.registerUser(username: "bob", password: "bob-pass", confirmation: "bob-pass")
            let bobID = store.addNote()
            store.updateNote(id: bobID, title: "Bob 数据", body: "将被销毁")
            store.lock()

            guard let alice = store.accounts.first(where: { $0.displayName == "alice" }) else {
                return XCTFail("应该存在 alice 账户")
            }
            store.unlock(userID: alice.id, password: "alice-pass")
            store.deleteCurrentUser(password: "wrong", confirmationText: "删除我的账户")
            XCTAssertEqual(store.accounts.map(\.displayName).sorted(), ["alice", "bob"])

            store.deleteCurrentUser(password: "alice-pass", confirmationText: "删除我的账户")
            XCTAssertEqual(store.accounts.map(\.displayName), ["bob"])
            store.unlock(username: "alice", password: "alice-pass")
            XCTAssertEqual(store.state, .locked)
            store.unlock(username: "bob", password: "bob-pass")
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.notes.first?.body, "将被销毁")

            let file = try JSONDecoder().decode(VaultFile.self, from: Data(contentsOf: url))
            XCTAssertEqual(file.users.count, 1)
            XCTAssertEqual(file.users.first?.displayName, "bob")
        }
    }

    func testDeletingCurrentLastUserRefreshesLockedVaultState() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "solo", password: "solo-pass", confirmation: "solo-pass")

            guard store.accounts.first != nil else {
                return XCTFail("应该存在 solo 账户")
            }
            XCTAssertEqual(store.userCount, 1)
            XCTAssertEqual(store.state, .unlocked)

            store.deleteCurrentUser(password: "solo-pass", confirmationText: "删除我的账户")

            XCTAssertEqual(store.state, .needsAdminSetup)
            XCTAssertEqual(store.userCount, 0)
            XCTAssertTrue(store.accounts.isEmpty)
            XCTAssertTrue(store.notes.isEmpty)
            XCTAssertNil(store.signedInUsername)

            let file = try JSONDecoder().decode(VaultFile.self, from: Data(contentsOf: url))
            XCTAssertTrue(file.users.isEmpty)
        }
    }

    func testDuplicateNoteCreatesIndependentCopy() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "writer", password: "pass", confirmation: "pass")
            let originalID = store.addNote()
            store.updateNote(id: originalID, title: "计划", body: "第一版")

            guard let copyID = store.duplicateNote(id: originalID) else {
                return XCTFail("应该能复制笔记")
            }
            XCTAssertNotEqual(originalID, copyID)
            XCTAssertEqual(store.notes.count, 2)
            XCTAssertEqual(store.notes.first?.id, copyID)
            XCTAssertEqual(store.notes.first?.title, "计划 副本")
            XCTAssertEqual(store.notes.first?.body, "第一版")

            store.updateNote(id: copyID, body: "副本已修改")
            XCTAssertEqual(store.notes.first(where: { $0.id == originalID })?.body, "第一版")
            XCTAssertEqual(store.notes.first(where: { $0.id == copyID })?.body, "副本已修改")
        }
    }

    func testVaultFilesAreIndependentEncryptedAndDeleteOriginalAfterImport() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let sourceURL = directory.appendingPathComponent("secret-photo.txt")
            let secretData = Data("这是一张图片里的秘密内容".utf8)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try secretData.write(to: sourceURL)

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "files", password: "pass", confirmation: "pass")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "纯文字笔记", body: "照片不应该挂在这里")
            store.importFilesToVault(urls: [sourceURL], deleteOriginals: true)

            XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path), "原照片/原文件应该在成功移入保险柜后删除")
            XCTAssertEqual(store.notes.first(where: { $0.id == noteID })?.attachments.count, 0)
            guard let item = store.vaultItems.first else {
                return XCTFail("应该已经移入独立保险柜")
            }
            XCTAssertEqual(item.fileName, "secret-photo.txt")
            XCTAssertEqual(store.vaultItemData(itemID: item.id), secretData)

            let vaultText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            XCTAssertFalse(vaultText.contains("这是一张图片里的秘密内容"))
            XCTAssertFalse(vaultText.contains("secret-photo.txt"))

            let attachmentRoot = directory.appendingPathComponent("Attachments")
            let encryptedFiles = (FileManager.default.enumerator(at: attachmentRoot, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                .filter { $0.pathExtension == "bin" }
            XCTAssertEqual(encryptedFiles.count, 1)
            let encryptedBlob = try Data(contentsOf: encryptedFiles[0])
            XCTAssertNotEqual(encryptedBlob, secretData)
            XCTAssertFalse(String(decoding: encryptedBlob, as: UTF8.self).contains("这是一张图片里的秘密内容"))

            store.lock()
            XCTAssertTrue(store.vaultItems.isEmpty)
            XCTAssertNil(store.vaultItemData(itemID: item.id))
            store.unlock(username: "files", password: "pass")
            XCTAssertEqual(store.vaultItems.first?.fileName, "secret-photo.txt")
            XCTAssertEqual(store.vaultItemData(itemID: item.id), secretData)

            store.deleteVaultItem(itemID: item.id)
            XCTAssertTrue(store.vaultItems.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: encryptedFiles[0].path))
        }
    }

    func testMultipleVaultFilesDeleteOriginalsAndStaySeparateFromNotes() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let firstURL = directory.appendingPathComponent("a.jpg")
            let secondURL = directory.appendingPathComponent("b.pdf")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("PHOTO-A".utf8).write(to: firstURL)
            try Data("PDF-B".utf8).write(to: secondURL)

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "safe", password: "pass", confirmation: "pass")
            _ = store.addNote()
            store.importFilesToVault(urls: [firstURL, secondURL], deleteOriginals: true)

            XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
            XCTAssertEqual(store.vaultItems.map(\.fileName).sorted(), ["a.jpg", "b.pdf"])
            XCTAssertTrue(store.notes.allSatisfy { $0.attachments.isEmpty })
        }
    }

    func testLargeVaultFileUsesChunkedStorageAndStreamsBackOut() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let sourceURL = directory.appendingPathComponent("large-photo.raw")
            let exportedURL = directory.appendingPathComponent("large-photo-exported.raw")
            let payload = Data((0..<(5 * 1024 * 1024 + 123)).map { UInt8($0 % 251) })
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try payload.write(to: sourceURL)

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "large", password: "pass", confirmation: "pass")
            store.importFilesToVault(urls: [sourceURL], deleteOriginals: true)

            guard let item = store.vaultItems.first else {
                return XCTFail("应该已经移入保险柜")
            }
            XCTAssertEqual(item.byteCount, payload.count)
            XCTAssertEqual(store.vaultItemData(itemID: item.id), payload)

            let attachmentRoot = directory.appendingPathComponent("Attachments")
            let encryptedFiles = (FileManager.default.enumerator(at: attachmentRoot, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                .filter { $0.pathExtension == "bin" }
            XCTAssertEqual(encryptedFiles.count, 1)
            let encryptedPrefix = try Data(contentsOf: encryptedFiles[0]).prefix(Data("CNATTACH2\n".utf8).count)
            XCTAssertEqual(Data(encryptedPrefix), Data("CNATTACH2\n".utf8))

            store.exportVaultItem(itemID: item.id, to: exportedURL)
            XCTAssertEqual(try Data(contentsOf: exportedURL), payload)
        }
    }

    func testUserRecordLegacyShortcutMetadataDefaultsToDisabledForOldVaults() throws {
        let rawKey = try CryptoService.randomData(count: 32)
        let passwordSalt = try CryptoService.randomData(count: 16)
        let passwordKey = try CryptoService.deriveKey(password: "pass", salt: passwordSalt, rounds: CryptoService.defaultRounds)
        let encryptedNotes = try CryptoService.seal(try JSONEncoder().encode(VaultPayload(notes: [], vaultItems: [])), using: SymmetricKey(data: rawKey))
        let legacyLikeJSON: [String: Any] = [
            "id": UUID().uuidString,
            "displayName": "old",
            "passwordSalt": passwordSalt.base64EncodedString(),
            "wrappedVaultKey": try CryptoService.seal(rawKey, using: passwordKey).base64EncodedString(),
            "encryptedNotes": encryptedNotes.base64EncodedString(),
            "createdAt": 0,
            "updatedAt": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyLikeJSON)
        let user = try JSONDecoder().decode(UserRecord.self, from: data)
        XCTAssertFalse(user.touchIDEnabled)
        XCTAssertFalse(user.advancedDataProtectionEnabled)
        XCTAssertEqual(user.role, .standard)
    }

    func testAdvancedDataProtectionPersistsPerAccount() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "protected", password: "pass", confirmation: "pass")
            XCTAssertFalse(store.currentAccountAdvancedDataProtectionEnabled)

            store.autoLockMinutes = 15
            store.setAdvancedDataProtectionForCurrentAccount(true)
            XCTAssertTrue(store.currentAccountAdvancedDataProtectionEnabled)
            XCTAssertEqual(store.autoLockMinutes, 1)

            store.lock()
            store.autoLockMinutes = 15
            store.unlock(username: "protected", password: "pass")
            XCTAssertTrue(store.currentAccountAdvancedDataProtectionEnabled)
            XCTAssertEqual(store.autoLockMinutes, 1)
            XCTAssertEqual(store.accounts.first?.advancedDataProtectionEnabled, true)
        }
    }

    func testAccountsAreEqualLocalAccounts() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "owner", password: "owner", confirmation: "owner")
            XCTAssertEqual(store.accounts.first(where: { $0.displayName == "owner" })?.role, .standard)

            store.registerUser(username: "guest", password: "guest", confirmation: "guest")
            XCTAssertEqual(store.accounts.first(where: { $0.displayName == "guest" })?.role, .standard)
            XCTAssertEqual(store.accounts.first(where: { $0.displayName == "owner" })?.role, .standard)
            XCTAssertEqual(store.accounts.first(where: { $0.displayName == "guest" })?.role, .standard)
        }
    }

    func testRegisteringNewUsersDoesNotRequireAdminPassword() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "owner", password: "owner", confirmation: "owner")
            XCTAssertEqual(store.state, .unlocked)
            store.lock()

            store.registerUser(username: "fresh", password: "fresh", confirmation: "fresh")
            XCTAssertEqual(store.accounts.first(where: { $0.displayName == "fresh" })?.role, .standard)
        }
    }

    func testCurrentUserPasswordCanBeChanged() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "owner", password: "old-pass", confirmation: "old-pass")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "Keep", body: "Still here")

            store.changeCurrentUserPassword(currentPassword: "wrong", newPassword: "new-pass", confirmation: "new-pass")
            store.lock()
            store.unlock(username: "owner", password: "new-pass")
            XCTAssertEqual(store.state, .locked)

            store.unlock(username: "owner", password: "old-pass")
            XCTAssertEqual(store.state, .unlocked)
            store.changeCurrentUserPassword(currentPassword: "old-pass", newPassword: "new-pass", confirmation: "new-pass")
            XCTAssertEqual(store.errorMessage, "当前账户密码已更新")
            store.lock()
            store.unlock(username: "owner", password: "old-pass")
            XCTAssertEqual(store.state, .locked)
            store.unlock(username: "owner", password: "new-pass")
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.notes.first?.body, "Still here")
        }
    }

    func testEraseAllDataRequiresCurrentUserPasswordAndConfirmation() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "owner", password: "owner", confirmation: "owner")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "Keep?", body: "No")
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

            store.eraseAllDataAndStartFresh(currentPassword: "wrong", confirmationText: "清空全部数据")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(store.state, .unlocked)

            store.eraseAllDataAndStartFresh(currentPassword: "owner", confirmationText: "清空全部数据")
            XCTAssertEqual(store.state, .needsAdminSetup)
            XCTAssertEqual(store.userCount, 0)
            XCTAssertTrue(store.accounts.isEmpty)
            XCTAssertTrue(store.notes.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testEncryptedSharedNoteFileCanMoveBetweenUsers() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "alice", password: "a", confirmation: "a")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "给 Bob", body: "这是一条共享内容")
            guard let package = store.exportSharedNote(id: noteID, sharePassword: "share") else {
                return XCTFail("应该能导出共享文件")
            }
            let packageText = String(decoding: package, as: UTF8.self)
            XCTAssertFalse(packageText.contains("这是一条共享内容"))
            XCTAssertFalse(packageText.contains("给 Bob"))
            store.lock()

            store.registerUser(username: "bob", password: "b", confirmation: "b")
            XCTAssertNil(store.importSharedNote(data: package, sharePassword: "wrong"))
            XCTAssertEqual(store.notes.count, 0)
            let importedID = store.importSharedNote(data: package, sharePassword: "share")
            XCTAssertNotNil(importedID)
            XCTAssertEqual(store.notes.count, 1)
            XCTAssertEqual(store.notes.first?.title, "共享：给 Bob")
            XCTAssertTrue(store.notes.first?.body.contains("这是一条共享内容") == true)
        }
    }

    func testUsernameHashIsNormalizedAndSalted() throws {
        let firstSalt = Data(repeating: 1, count: 16)
        let secondSalt = Data(repeating: 2, count: 16)
        XCTAssertEqual(
            CryptoService.usernameHash("  Alice  ", salt: firstSalt),
            CryptoService.usernameHash("alice", salt: firstSalt)
        )
        XCTAssertNotEqual(
            CryptoService.usernameHash("alice", salt: firstSalt),
            CryptoService.usernameHash("alice", salt: secondSalt)
        )
    }

    func testExistingVaultMigratesToLocalUsernameWithoutLosingNotes() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let password = "the-existing-master-password"
            let salt = try CryptoService.randomData(count: 16)
            let rawKey = try CryptoService.randomData(count: 32)
            let passwordKey = try CryptoService.deriveKey(password: password, salt: salt, rounds: 1_000)
            let wrappedKey = try CryptoService.seal(rawKey, using: passwordKey)
            let legacyNotes = [Note(title: "旧笔记", body: "迁移后仍然存在")]
            let encryptedNotes = try CryptoService.seal(
                try JSONEncoder().encode(legacyNotes),
                using: SymmetricKey(data: rawKey)
            )
            let legacyFile = LegacyVaultFile(
                version: 1,
                salt: salt,
                rounds: 1_000,
                wrappedVaultKey: wrappedKey,
                encryptedNotes: encryptedNotes,
                updatedAt: .now
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(legacyFile).write(to: url)

            let store = VaultStore(vaultURL: url)
            XCTAssertEqual(store.state, .needsMigration)
            store.migrateLegacyVault(username: "new-local-user", oldPassword: password)
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.notes, legacyNotes)
            XCTAssertNotNil(store.recoveryCodeToShow)

            let migratedData = try Data(contentsOf: url)
            let migrated = try JSONDecoder().decode(VaultFile.self, from: migratedData)
            XCTAssertEqual(migrated.version, 2)
            XCTAssertEqual(migrated.users.count, 1)
            XCTAssertNotNil(migrated.users.first?.usernameSalt)
            XCTAssertNotNil(migrated.users.first?.usernameHash)
            XCTAssertTrue(String(decoding: migratedData, as: UTF8.self).contains("new-local-user"))
            XCTAssertEqual(store.accounts.map(\.displayName), ["new-local-user"])

            store.lock()
            store.unlock(username: "new-local-user", password: password)
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertEqual(store.notes, legacyNotes)
        }
    }

    func testLegacyVaultCanBeDiscardedToStartFresh() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let password = "the-existing-master-password"
            let salt = try CryptoService.randomData(count: 16)
            let rawKey = try CryptoService.randomData(count: 32)
            let passwordKey = try CryptoService.deriveKey(password: password, salt: salt, rounds: 1_000)
            let legacyFile = LegacyVaultFile(
                version: 1,
                salt: salt,
                rounds: 1_000,
                wrappedVaultKey: try CryptoService.seal(rawKey, using: passwordKey),
                encryptedNotes: try CryptoService.seal(try JSONEncoder().encode([Note(title: "旧数据", body: "将被清空")]), using: SymmetricKey(data: rawKey)),
                updatedAt: .now
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(legacyFile).write(to: url)

            let store = VaultStore(vaultURL: url)
            XCTAssertEqual(store.state, .needsMigration)
            store.discardLegacyVaultAndStartFresh()
            XCTAssertEqual(store.state, .needsAdminSetup)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

            store.registerUser(username: "fresh-user", password: "fresh-user-password", confirmation: "fresh-user-password")
            XCTAssertEqual(store.state, .unlocked)
            XCTAssertTrue(store.notes.isEmpty)
        }
    }

    func testNoteOrganizationMetadataPersistsAndOldNotesDecode() async throws {
        let oldJSON = """
        {
          "id": "\(UUID().uuidString)",
          "title": "旧格式",
          "body": "没有新字段也应该能打开",
          "attachments": [],
          "createdAt": "2026-06-27T00:00:00Z",
          "updatedAt": "2026-06-27T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldNote = try decoder.decode(Note.self, from: Data(oldJSON.utf8))
        XCTAssertFalse(oldNote.isPinned)
        XCTAssertFalse(oldNote.isFavorite)
        XCTAssertFalse(oldNote.isArchived)
        XCTAssertTrue(oldNote.tags.isEmpty)

        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "organizer", password: "pass", confirmation: "pass")
            let id = store.addNote()
            store.updateNote(id: id, title: "项目计划", body: "大量新功能")
            store.togglePinned(noteID: id)
            store.toggleFavorite(noteID: id)
            store.updateTags(noteID: id, tags: ["工作", "隐私", "工作"])

            store.lock()
            store.unlock(username: "organizer", password: "pass")

            let note = try XCTUnwrap(store.notes.first(where: { $0.id == id }))
            XCTAssertTrue(note.isPinned)
            XCTAssertTrue(note.isFavorite)
            XCTAssertFalse(note.isArchived)
            XCTAssertEqual(note.tags, ["工作", "隐私"])
        }
    }

    func testSecurityLogsPersistEncryptedAndAvoidSensitiveContent() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            let sourceURL = directory.appendingPathComponent("secret-contract-name.txt")
            defer { try? FileManager.default.removeItem(at: directory) }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("file secret body".utf8).write(to: sourceURL)

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "logger", password: "pass", confirmation: "pass")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "Hidden title", body: "Hidden body")
            store.importFilesToVault(urls: [sourceURL], deleteOriginals: true)
            guard let item = store.vaultItems.first else {
                return XCTFail("应该已经导入保险柜文件")
            }
            store.deleteVaultItem(itemID: item.id)

            XCTAssertTrue(store.securityLogs.contains { $0.eventType == .vaultFilesImported })
            XCTAssertTrue(store.securityLogs.contains { $0.eventType == .vaultFileDeleted })
            let logText = store.securityLogs.map(\.message).joined(separator: "\n")
            XCTAssertFalse(logText.contains("secret-contract-name"))
            XCTAssertFalse(logText.contains("Hidden title"))
            XCTAssertFalse(logText.contains("Hidden body"))

            let diskText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            XCTAssertFalse(diskText.contains("导入保险柜文件"))
            XCTAssertFalse(diskText.contains("secret-contract-name"))

            store.lock()
            store.unlock(username: "logger", password: "pass")
            XCTAssertTrue(store.securityLogs.contains { $0.eventType == .vaultFilesImported })
        }
    }

    func testAdvancedProtectionBlocksSensitiveExportsAndClearsLogsWithAuthorization() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "protected-logger", password: "pass", confirmation: "pass")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "Do not export", body: "Sensitive")
            store.setAdvancedDataProtectionForCurrentAccount(true)

            XCTAssertNil(store.exportSharedNote(id: noteID, sharePassword: "share"))
            XCTAssertNil(store.importSharedNote(data: Data("not a package".utf8), sharePassword: "share"))
            XCTAssertTrue(store.securityLogs.contains { $0.eventType == .protectedActionBlocked && $0.result == .blocked })

            store.clearSecurityLogs(currentPassword: "wrong", confirmationText: "清空安全日志")
            XCTAssertTrue(store.securityLogs.contains { $0.eventType == .protectedActionBlocked })

            store.clearSecurityLogs(currentPassword: "pass", confirmationText: "清空安全日志")
            XCTAssertEqual(store.securityLogs.count, 1)
            XCTAssertEqual(store.securityLogs.first?.eventType, .securityLogsCleared)
        }
    }

    func testDecoyPasswordOpensPersistentEncryptedDecoySpace() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "owner", password: "real-pass", confirmation: "real-pass")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "Real", body: "Real secret")
            store.setDecoyPasswordForCurrentAccount(
                currentPassword: "real-pass",
                decoyPassword: "fake-pass",
                confirmation: "fake-pass",
                action: .openDecoySpace
            )
            XCTAssertTrue(store.currentAccountDecoyPasswordEnabled)
            store.lock()

            XCTAssertTrue(store.unlock(username: "owner", password: "fake-pass"))
            XCTAssertTrue(store.isDecoySession)
            XCTAssertTrue(store.notes.isEmpty)
            let fakeID = store.addNote()
            store.updateNote(id: fakeID, title: "Fake", body: "Fake content")
            XCTAssertEqual(store.notes.first?.title, "Fake")
            store.lock()

            XCTAssertTrue(store.unlock(username: "owner", password: "real-pass"))
            XCTAssertFalse(store.isDecoySession)
            XCTAssertEqual(store.notes.count, 1)
            XCTAssertEqual(store.notes.first?.title, "Real")
            XCTAssertEqual(store.notes.first?.body, "Real secret")
            store.lock()

            XCTAssertTrue(store.unlock(username: "owner", password: "fake-pass"))
            XCTAssertTrue(store.isDecoySession)
            XCTAssertEqual(store.notes.count, 1)
            XCTAssertEqual(store.notes.first?.title, "Fake")
            XCTAssertEqual(store.notes.first?.body, "Fake content")
        }
    }

    func testDecoyPasswordCanEraseLocalVaultWhenConfigured() async throws {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let url = directory.appendingPathComponent("vault.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let store = VaultStore(vaultURL: url)
            store.registerUser(username: "owner", password: "real-pass", confirmation: "real-pass")
            let noteID = store.addNote()
            store.updateNote(id: noteID, title: "Real", body: "Destroy me")
            store.setDecoyPasswordForCurrentAccount(
                currentPassword: "real-pass",
                decoyPassword: "wipe-pass",
                confirmation: "wipe-pass",
                action: .eraseLocalData
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            store.lock()

            XCTAssertTrue(store.unlock(username: "owner", password: "wipe-pass"))
            XCTAssertEqual(store.state, .needsAdminSetup)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(store.accounts.isEmpty)
            XCTAssertTrue(store.notes.isEmpty)
        }
    }
}
