import CryptoKit
import Foundation

enum VaultPersistenceError: Error {
    case invalidPayload
    case incompleteTransaction
}

/// Coordinates durable vault metadata writes and whole-vault restoration.
/// The journal contains only operation metadata and hashes, never user content.
enum VaultPersistence {
    private enum Operation: String, Codable {
        case write
        case restore
    }

    private struct Journal: Codable {
        let version: Int
        let operation: Operation
        let expectedVaultHash: String
        let stagingDirectoryName: String?
        let startedAt: Date
    }

    static func recoverIfNeeded(
        vaultURL: URL,
        attachmentsURL: URL,
        isValidVaultData: (Data) -> Bool
    ) throws {
        let journalURL = transactionJournalURL(for: vaultURL)
        guard FileManager.default.fileExists(atPath: journalURL.path) else {
            try recoverPrimaryIfNeeded(vaultURL: vaultURL, isValidVaultData: isValidVaultData)
            return
        }
        guard let journalData = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(Journal.self, from: journalData),
              journal.version == 1 else {
            try? FileManager.default.removeItem(at: journalURL)
            try recoverPrimaryIfNeeded(vaultURL: vaultURL, isValidVaultData: isValidVaultData)
            return
        }

        switch journal.operation {
        case .write:
            try recoverInterruptedWrite(
                vaultURL: vaultURL,
                expectedHash: journal.expectedVaultHash,
                isValidVaultData: isValidVaultData
            )
        case .restore:
            try recoverInterruptedRestore(
                vaultURL: vaultURL,
                attachmentsURL: attachmentsURL,
                journal: journal,
                isValidVaultData: isValidVaultData
            )
        }
        try? FileManager.default.removeItem(at: journalURL)
    }

    static func write(
        _ data: Data,
        to vaultURL: URL,
        isValidVaultData: (Data) -> Bool
    ) throws {
        guard isValidVaultData(data) else { throw VaultPersistenceError.invalidPayload }
        let manager = FileManager.default
        let directory = vaultURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let pendingURL = pendingVaultURL(for: vaultURL)
        let previousURL = previousVaultURL(for: vaultURL)
        let journal = Journal(
            version: 1,
            operation: .write,
            expectedVaultHash: sha256Hex(data),
            stagingDirectoryName: nil,
            startedAt: .now
        )
        try writeDurably(try JSONEncoder().encode(journal), to: transactionJournalURL(for: vaultURL))
        try writeDurably(data, to: pendingURL)
        guard let pendingData = try? Data(contentsOf: pendingURL), isValidVaultData(pendingData) else {
            throw VaultPersistenceError.invalidPayload
        }

        if let existing = try? Data(contentsOf: vaultURL), isValidVaultData(existing) {
            try writeDurably(existing, to: previousURL)
        }
        try replaceItem(at: vaultURL, with: pendingURL)
        try? manager.removeItem(at: transactionJournalURL(for: vaultURL))
    }

    static func restore(
        vaultURL: URL,
        attachmentsURL: URL,
        backupVaultURL: URL,
        backupAttachmentsURL: URL?,
        isValidVaultData: (Data) -> Bool
    ) throws {
        let manager = FileManager.default
        let backupData = try Data(contentsOf: backupVaultURL)
        guard isValidVaultData(backupData) else { throw VaultPersistenceError.invalidPayload }

        let identifier = UUID().uuidString
        let stagingURL = vaultURL.deletingLastPathComponent()
            .appendingPathComponent(".ciphernotes-restore-\(identifier)", isDirectory: true)
        try manager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let stagedVaultURL = stagingURL.appendingPathComponent("vault.json")
        try writeDurably(backupData, to: stagedVaultURL)
        if let backupAttachmentsURL,
           manager.fileExists(atPath: backupAttachmentsURL.path) {
            try manager.copyItem(
                at: backupAttachmentsURL,
                to: stagingURL.appendingPathComponent("Attachments", isDirectory: true)
            )
        }

        let journal = Journal(
            version: 1,
            operation: .restore,
            expectedVaultHash: sha256Hex(backupData),
            stagingDirectoryName: stagingURL.lastPathComponent,
            startedAt: .now
        )
        try writeDurably(try JSONEncoder().encode(journal), to: transactionJournalURL(for: vaultURL))
        try installStagedRestore(
            vaultURL: vaultURL,
            attachmentsURL: attachmentsURL,
            stagingURL: stagingURL,
            expectedHash: journal.expectedVaultHash,
            isValidVaultData: isValidVaultData
        )
        try? manager.removeItem(at: transactionJournalURL(for: vaultURL))
    }

    private static func recoverInterruptedWrite(
        vaultURL: URL,
        expectedHash: String,
        isValidVaultData: (Data) -> Bool
    ) throws {
        let pendingURL = pendingVaultURL(for: vaultURL)
        if isExpectedVault(at: vaultURL, hash: expectedHash, validator: isValidVaultData) {
            try? FileManager.default.removeItem(at: pendingURL)
            return
        }
        if isExpectedVault(at: pendingURL, hash: expectedHash, validator: isValidVaultData) {
            try replaceItem(at: vaultURL, with: pendingURL)
            return
        }
        try recoverPrimaryIfNeeded(vaultURL: vaultURL, isValidVaultData: isValidVaultData)
    }

    private static func recoverInterruptedRestore(
        vaultURL: URL,
        attachmentsURL: URL,
        journal: Journal,
        isValidVaultData: (Data) -> Bool
    ) throws {
        guard let stagingDirectoryName = journal.stagingDirectoryName else {
            throw VaultPersistenceError.incompleteTransaction
        }
        let stagingURL = vaultURL.deletingLastPathComponent()
            .appendingPathComponent(stagingDirectoryName, isDirectory: true)
        if isExpectedVault(at: vaultURL, hash: journal.expectedVaultHash, validator: isValidVaultData) {
            try finishAttachmentInstallIfNeeded(attachmentsURL: attachmentsURL, stagingURL: stagingURL)
            cleanupRestoreArtifacts(vaultURL: vaultURL, attachmentsURL: attachmentsURL, stagingURL: stagingURL)
            return
        }
        if isExpectedVault(
            at: stagingURL.appendingPathComponent("vault.json"),
            hash: journal.expectedVaultHash,
            validator: isValidVaultData
        ) {
            try installStagedRestore(
                vaultURL: vaultURL,
                attachmentsURL: attachmentsURL,
                stagingURL: stagingURL,
                expectedHash: journal.expectedVaultHash,
                isValidVaultData: isValidVaultData
            )
            return
        }
        try rollbackRestore(vaultURL: vaultURL, attachmentsURL: attachmentsURL)
    }

    private static func installStagedRestore(
        vaultURL: URL,
        attachmentsURL: URL,
        stagingURL: URL,
        expectedHash: String,
        isValidVaultData: (Data) -> Bool
    ) throws {
        let manager = FileManager.default
        let stagedVaultURL = stagingURL.appendingPathComponent("vault.json")
        guard isExpectedVault(at: stagedVaultURL, hash: expectedHash, validator: isValidVaultData) else {
            throw VaultPersistenceError.invalidPayload
        }
        let rollbackVaultURL = restoreRollbackVaultURL(for: vaultURL)
        let rollbackAttachmentsURL = restoreRollbackAttachmentsURL(for: attachmentsURL)
        try? manager.removeItem(at: rollbackVaultURL)
        try? manager.removeItem(at: rollbackAttachmentsURL)
        if manager.fileExists(atPath: vaultURL.path) {
            try manager.moveItem(at: vaultURL, to: rollbackVaultURL)
        }
        if manager.fileExists(atPath: attachmentsURL.path) {
            try manager.moveItem(at: attachmentsURL, to: rollbackAttachmentsURL)
        }

        do {
            try manager.moveItem(at: stagedVaultURL, to: vaultURL)
            try finishAttachmentInstallIfNeeded(attachmentsURL: attachmentsURL, stagingURL: stagingURL)
            guard isExpectedVault(at: vaultURL, hash: expectedHash, validator: isValidVaultData) else {
                throw VaultPersistenceError.invalidPayload
            }
            cleanupRestoreArtifacts(vaultURL: vaultURL, attachmentsURL: attachmentsURL, stagingURL: stagingURL)
        } catch {
            try? rollbackRestore(vaultURL: vaultURL, attachmentsURL: attachmentsURL)
            throw error
        }
    }

    private static func finishAttachmentInstallIfNeeded(attachmentsURL: URL, stagingURL: URL) throws {
        let manager = FileManager.default
        let stagedAttachmentsURL = stagingURL.appendingPathComponent("Attachments", isDirectory: true)
        guard manager.fileExists(atPath: stagedAttachmentsURL.path) else {
            if !manager.fileExists(atPath: attachmentsURL.path) {
                try manager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            }
            return
        }
        if manager.fileExists(atPath: attachmentsURL.path) {
            try manager.removeItem(at: attachmentsURL)
        }
        try manager.moveItem(at: stagedAttachmentsURL, to: attachmentsURL)
    }

    private static func rollbackRestore(vaultURL: URL, attachmentsURL: URL) throws {
        let manager = FileManager.default
        let rollbackVaultURL = restoreRollbackVaultURL(for: vaultURL)
        let rollbackAttachmentsURL = restoreRollbackAttachmentsURL(for: attachmentsURL)
        if manager.fileExists(atPath: rollbackVaultURL.path) {
            try? manager.removeItem(at: vaultURL)
            try manager.moveItem(at: rollbackVaultURL, to: vaultURL)
        }
        if manager.fileExists(atPath: rollbackAttachmentsURL.path) {
            try? manager.removeItem(at: attachmentsURL)
            try manager.moveItem(at: rollbackAttachmentsURL, to: attachmentsURL)
        }
    }

    private static func recoverPrimaryIfNeeded(
        vaultURL: URL,
        isValidVaultData: (Data) -> Bool
    ) throws {
        if let primary = try? Data(contentsOf: vaultURL), isValidVaultData(primary) { return }
        let previousURL = previousVaultURL(for: vaultURL)
        guard let previous = try? Data(contentsOf: previousURL), isValidVaultData(previous) else {
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                throw VaultPersistenceError.invalidPayload
            }
            return
        }
        try writeDurably(previous, to: vaultURL)
    }

    private static func cleanupRestoreArtifacts(vaultURL: URL, attachmentsURL: URL, stagingURL: URL) {
        let manager = FileManager.default
        try? manager.removeItem(at: restoreRollbackVaultURL(for: vaultURL))
        try? manager.removeItem(at: restoreRollbackAttachmentsURL(for: attachmentsURL))
        try? manager.removeItem(at: stagingURL)
    }

    private static func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destinationURL.path) {
            try manager.removeItem(at: destinationURL)
        }
        try manager.moveItem(at: sourceURL, to: destinationURL)
    }

    private static func writeDurably(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: url)
        guard manager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private static func isExpectedVault(
        at url: URL,
        hash: String,
        validator: (Data) -> Bool
    ) -> Bool {
        guard let data = try? Data(contentsOf: url), validator(data) else { return false }
        return sha256Hex(data) == hash
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func pendingVaultURL(for vaultURL: URL) -> URL {
        vaultURL.deletingPathExtension().appendingPathExtension("pending.json")
    }

    private static func previousVaultURL(for vaultURL: URL) -> URL {
        vaultURL.deletingPathExtension().appendingPathExtension("previous.json")
    }

    private static func transactionJournalURL(for vaultURL: URL) -> URL {
        vaultURL.deletingPathExtension().appendingPathExtension("transaction.json")
    }

    private static func restoreRollbackVaultURL(for vaultURL: URL) -> URL {
        vaultURL.deletingPathExtension().appendingPathExtension("restore-rollback.json")
    }

    private static func restoreRollbackAttachmentsURL(for attachmentsURL: URL) -> URL {
        attachmentsURL.deletingLastPathComponent().appendingPathComponent("Attachments.restore-rollback", isDirectory: true)
    }
}
