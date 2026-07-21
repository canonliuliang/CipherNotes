import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum VaultImportJobStatus: String, Sendable {
    case encrypting
    case paused
    case cancelling
    case finished
    case failed
    case cancelled

    var label: String {
        switch self {
        case .encrypting: "正在加密"
        case .paused: "已暂停"
        case .cancelling: "正在取消"
        case .finished: "已完成"
        case .failed: "导入失败"
        case .cancelled: "已取消"
        }
    }
}

struct VaultImportJob: Identifiable, Equatable, Sendable {
    let id: UUID
    var fileName: String
    var byteCount: Int
    var processedByteCount: Int
    var status: VaultImportJobStatus
    var startedAt: Date = .now
    var updatedAt: Date = .now

    var progress: Double {
        guard byteCount > 0 else { return status == .finished ? 1 : 0 }
        return min(1, max(0, Double(processedByteCount) / Double(byteCount)))
    }

    var isActive: Bool {
        status == .encrypting || status == .paused || status == .cancelling
    }

    var estimatedRemainingSeconds: TimeInterval? {
        guard status == .encrypting, processedByteCount > 0, byteCount > processedByteCount else { return nil }
        let elapsed = max(0.1, updatedAt.timeIntervalSince(startedAt))
        let bytesPerSecond = Double(processedByteCount) / elapsed
        guard bytesPerSecond > 0 else { return nil }
        return Double(byteCount - processedByteCount) / bytesPerSecond
    }
}

private final class VaultImportCancellationToken: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var paused = false

    func cancel() {
        condition.lock()
        cancelled = true
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    func pause() {
        condition.lock()
        guard !cancelled else { condition.unlock(); return }
        paused = true
        condition.unlock()
    }

    func resume() {
        condition.lock()
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    func waitIfPaused() {
        condition.lock()
        while paused && !cancelled { condition.wait() }
        condition.unlock()
    }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }
}

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var state: VaultState
    @Published private(set) var notes: [Note] = []
    @Published private(set) var vaultItems: [VaultAttachment] = []
    @Published private(set) var signedInUsername: String?
    @Published private(set) var userCount = 0
    @Published private(set) var accounts: [AccountSummary] = []
    @Published private(set) var securityLogs: [SecurityLogEntry] = []
    @Published private(set) var isDecoySession = false
    @Published private(set) var vaultImportJobs: [VaultImportJob] = []
    @Published private(set) var vaultDeletingItemIDs: Set<UUID> = []
    @Published var recoveryCodeToShow: String?
    @Published var errorMessage: String?
    @Published var autoLockMinutes = 5

    nonisolated private static let vaultVersion = 2
    nonisolated private static let sharedNoteVersion = 1
    nonisolated private static let maxSecurityLogEntries = 120
    nonisolated private static let decoyVerifierContext = Data("ciphernotes-decoy-password-v1".utf8)

    private let vaultURL: URL
    private var vaultKey: Data?
    private var vaultFile: VaultFile?
    private var currentUserID: UUID?
    private var eventMonitor: Any?
    private var idleTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var vaultImportCancellationTokens: [UUID: VaultImportCancellationToken] = [:]
    private var authenticationFailureCounts: [String: Int] = [:]
    private var authenticationBlockedUntil: [String: Date] = [:]
    private var lastActivity = Date()
    private struct PreviewCacheEntry {
        let image: NSImage
        let cost: Int
        var lastAccess: UInt64
    }
    private var imagePreviewCache: [UUID: PreviewCacheEntry] = [:]
    private var previewCacheClock: UInt64 = 0
    private var previewCacheCost = 0
    nonisolated private static let maxPreviewSourceBytes = 64 * 1024 * 1024
    nonisolated private static let maxPreviewCacheCost = 48 * 1024 * 1024
    nonisolated private static let maxPreviewCacheItems = 32
    // Keep encryption of moderately sized files off the main actor. Tiny files
    // still use the synchronous path to avoid task setup overhead.
    nonisolated private static let backgroundImportThresholdBytes = 4 * 1024 * 1024
    nonisolated private static let attachmentMagic = Data("CNATTACH2\n".utf8)
    nonisolated private static let attachmentChunkSize = 4 * 1024 * 1024
    nonisolated private static let attachmentChunkOverhead = 12 + 16
    nonisolated private static let maxEncryptedAttachmentChunkSize = attachmentChunkSize + attachmentChunkOverhead
    nonisolated private static let maxSharedPackageBytes = 128 * 1024 * 1024
    nonisolated private static let maxSharedAttachments = 100
    nonisolated private static let maxSharedAttachmentBytes = 64 * 1024 * 1024
    nonisolated private static let maxSharedTotalAttachmentBytes = 128 * 1024 * 1024

    private struct UserBuild {
        var user: UserRecord
        let recoveryCode: String
    }

    private struct BackupManifest: Codable {
        let formatVersion: Int
        let vaultVersion: Int
        let createdAt: Date
        let fileHashes: [String: String]
    }

    private static func placeholderAdminFields(rounds: UInt32 = CryptoService.defaultRounds) throws -> (salt: Data, verifier: Data) {
        let salt = try CryptoService.randomData(count: 16)
        _ = rounds
        return (salt, try CryptoService.randomData(count: 32))
    }

    init(vaultURL: URL? = nil) {
        self.vaultURL = vaultURL ?? Self.defaultVaultURL()
        state = Self.initialState(for: self.vaultURL)
        userCount = Self.userCount(at: self.vaultURL)
        accounts = Self.accountSummaries(at: self.vaultURL)
        cleanOrphanedAttachments()
        ensureAttachmentsNeverIndexed()
        installPrivacyObservers()
    }

    func migrateLegacyVault(username: String, oldPassword: String) {
        guard !oldPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = VaultError.passwordRequired.localizedDescription
            return
        }
        let normalizedUsername: String
        do {
            normalizedUsername = try validateUsernameFormat(username)
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? error.localizedDescription
            return
        }
        do {
            let legacy = try readLegacyFile()
            if let salt = legacy.usernameSalt, let expected = legacy.usernameHash {
                guard CryptoService.usernameHash(normalizedUsername, salt: salt) == expected else {
                    throw VaultError.invalidUsername
                }
            }

            let oldPasswordKey = try CryptoService.deriveKey(password: oldPassword, salt: legacy.salt, rounds: legacy.rounds)
            let rawKey = try CryptoService.open(legacy.wrappedVaultKey, using: oldPasswordKey)
            _ = try decodeNotes(from: legacy.encryptedNotes, rawKey: rawKey)

            let compatibility = try Self.placeholderAdminFields()
            var built = try makeUser(username: normalizedUsername, displayName: Self.displayName(for: username), password: oldPassword, existingVaultKey: rawKey, existingEncryptedNotes: legacy.encryptedNotes)
            built.user.role = .standard
            let file = VaultFile(
                version: Self.vaultVersion,
                rounds: CryptoService.defaultRounds,
                adminSalt: compatibility.salt,
                adminVerifier: compatibility.verifier,
                users: [built.user],
                updatedAt: .now
            )
            try write(file)
            try finishUnlock(file: file, user: built.user, rawKey: rawKey, username: built.user.displayName ?? Self.displayName(for: username))
            recoveryCodeToShow = built.recoveryCode
            userCount = file.users.count
            refreshAccounts(from: file)
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "升级失败"
        }
    }

    func discardLegacyVaultAndStartFresh() {
        do {
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                try FileManager.default.removeItem(at: vaultURL)
            }
            try? FileManager.default.removeItem(at: attachmentsRootURL())
            vaultFile = nil
            vaultKey = nil
            currentUserID = nil
            notes.removeAll(keepingCapacity: false)
            vaultItems.removeAll(keepingCapacity: false)
            securityLogs.removeAll(keepingCapacity: false)
            isDecoySession = false
            imagePreviewCache.removeAll(keepingCapacity: false)
            signedInUsername = nil
            userCount = 0
            accounts = []
            recoveryCodeToShow = nil
            errorMessage = nil
            state = .needsAdminSetup
        } catch {
            errorMessage = "清空旧数据失败：\(error.localizedDescription)"
        }
    }

    func eraseAllDataAndStartFresh(currentPassword: String, confirmationText: String) {
        guard confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "清空全部数据" else {
            errorMessage = "请输入“清空全部数据”以确认"
            return
        }
        do {
            let file = try readVaultFile()
            try validateCurrentUserPassword(currentPassword, against: file)
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                try FileManager.default.removeItem(at: vaultURL)
            }
            let attachmentsRoot = attachmentsRootURL()
            if FileManager.default.fileExists(atPath: attachmentsRoot.path) {
                try FileManager.default.removeItem(at: attachmentsRoot)
            }
            vaultFile = nil
            vaultKey = nil
            currentUserID = nil
            notes.removeAll(keepingCapacity: false)
            vaultItems.removeAll(keepingCapacity: false)
            securityLogs.removeAll(keepingCapacity: false)
            isDecoySession = false
            imagePreviewCache.removeAll(keepingCapacity: false)
            signedInUsername = nil
            userCount = 0
            accounts = []
            recoveryCodeToShow = nil
            autoLockMinutes = 5
            state = .needsAdminSetup
            errorMessage = nil
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "清空全部数据失败"
        }
    }

    func registerUser(
        username: String,
        password: String,
        confirmation: String
    ) {
        let normalizedUsername: String
        do {
            normalizedUsername = try validateUsernameFormat(username)
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? error.localizedDescription
            return
        }
        guard password == confirmation else {
            errorMessage = "两次输入的用户密码不一致"
            return
        }
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = VaultError.passwordRequired.localizedDescription
            return
        }
        do {
            var file: VaultFile
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                file = try readVaultFile()
            } else {
                let compatibility = try Self.placeholderAdminFields()
                file = VaultFile(
                    version: Self.vaultVersion,
                    rounds: CryptoService.defaultRounds,
                    adminSalt: compatibility.salt,
                    adminVerifier: compatibility.verifier,
                    users: [],
                    updatedAt: .now
                )
            }
            guard try findUser(username: normalizedUsername, in: file) == nil else {
                throw VaultError.usernameTaken
            }
            let rawKey = try CryptoService.randomData(count: 32)
            let emptyNotes = try CryptoService.seal(try JSONEncoder().encode(VaultPayload(notes: [], vaultItems: [])), using: SymmetricKey(data: rawKey))
            var built = try makeUser(username: normalizedUsername, displayName: Self.displayName(for: username), password: password, existingVaultKey: rawKey, existingEncryptedNotes: emptyNotes)
            built.user.role = .standard
            file.users.append(built.user)
            file.updatedAt = .now
            try write(file)
            try finishUnlock(file: file, user: built.user, rawKey: rawKey, username: built.user.displayName ?? Self.displayName(for: username))
            recoveryCodeToShow = built.recoveryCode
            recordSecurityEvent(.accountCreated, message: "本地账户已创建")
            userCount = file.users.count
            refreshAccounts(from: file)
            errorMessage = nil
            touchActivity()
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "注册失败"
        }
    }

    func resetPasswordWithRecoveryCode(username: String, recoveryCode: String, newPassword: String, confirmation: String) {
        guard newPassword == confirmation else {
            errorMessage = "两次输入的新密码不一致"
            return
        }
        guard !newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = VaultError.passwordRequired.localizedDescription
            return
        }
        do {
            var file = try readVaultFile()
            guard let index = try findUserIndex(username: username, in: file) else {
                throw VaultError.invalidUsername
            }
            let user = file.users[index]
            guard let recoverySalt = user.recoverySalt, let recoveryWrappedVaultKey = user.recoveryWrappedVaultKey else {
                throw VaultError.recoveryCodeMissing
            }
            let recoveryKey = try recoveryKey(for: recoveryCode, salt: recoverySalt)
            let rawKey = try CryptoService.open(recoveryWrappedVaultKey, using: recoveryKey)
            _ = try decodeNotes(from: user.encryptedNotes, rawKey: rawKey)

            let passwordSalt = try CryptoService.randomData(count: 16)
            let passwordKey = try CryptoService.deriveKey(password: newPassword, salt: passwordSalt, rounds: CryptoService.defaultRounds)
            let recovery = try makeRecoveryWrap(for: rawKey)
            file.users[index].passwordSalt = passwordSalt
            file.users[index].passwordKDF = PasswordKDFConfiguration(rounds: CryptoService.defaultRounds)
            file.users[index].wrappedVaultKey = try CryptoService.seal(rawKey, using: passwordKey)
            file.users[index].recoverySalt = recovery.salt
            file.users[index].recoveryWrappedVaultKey = recovery.wrappedVaultKey
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            try finishUnlock(file: file, user: file.users[index], rawKey: rawKey, username: file.users[index].displayName ?? Self.displayName(for: username))
            recoveryCodeToShow = recovery.code
            recordSecurityEvent(.passwordChanged, message: "已使用恢复码重设账户密码")
            recordSecurityEvent(.recoveryCodeGenerated, message: "恢复码已重新生成")
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "无法重设密码"
        }
    }

    func changeCurrentUserPassword(currentPassword: String, newPassword: String, confirmation: String) {
        guard newPassword == confirmation else {
            errorMessage = "两次输入的新密码不一致"
            return
        }
        guard !newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = VaultError.passwordRequired.localizedDescription
            return
        }
        do {
            var file = try readVaultFile()
            guard let currentUserID,
                  let index = file.users.firstIndex(where: { $0.id == currentUserID }) else {
                throw VaultError.invalidUsername
            }
            let user = file.users[index]
            let oldPasswordKey = try CryptoService.deriveKey(password: currentPassword, salt: user.passwordSalt, rounds: passwordRounds(for: user, in: file))
            let rawKey = try CryptoService.open(user.wrappedVaultKey, using: oldPasswordKey)
            _ = try decodePayload(from: user.encryptedNotes, rawKey: rawKey)

            let newSalt = try CryptoService.randomData(count: 16)
            let newPasswordKey = try CryptoService.deriveKey(password: newPassword, salt: newSalt, rounds: CryptoService.defaultRounds)
            let recovery = try makeRecoveryWrap(for: rawKey)
            file.users[index].passwordSalt = newSalt
            file.users[index].passwordKDF = PasswordKDFConfiguration(rounds: CryptoService.defaultRounds)
            file.users[index].wrappedVaultKey = try CryptoService.seal(rawKey, using: newPasswordKey)
            file.users[index].recoverySalt = recovery.salt
            file.users[index].recoveryWrappedVaultKey = recovery.wrappedVaultKey
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            vaultFile = file
            refreshAccounts(from: file)
            recoveryCodeToShow = recovery.code
            recordSecurityEvent(.passwordChanged, message: "当前账户密码已更新")
            recordSecurityEvent(.recoveryCodeGenerated, message: "密码更新后已生成新的恢复码")
            errorMessage = "当前账户密码已更新"
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "当前账户密码更新失败"
        }
    }

    @discardableResult
    func unlock(username: String, password: String) -> Bool {
        let identifier = "username:\(CryptoService.normalizedUsername(username))"
        guard canAttemptAuthentication(identifier) else { return false }
        do {
            let file = try readVaultFile()
            guard let user = try findUser(username: username, in: file) else {
                throw VaultError.invalidUsername
            }
            let passwordKey = try CryptoService.deriveKey(password: password, salt: user.passwordSalt, rounds: passwordRounds(for: user, in: file))
            let rawKey = try CryptoService.open(user.wrappedVaultKey, using: passwordKey)
            try finishUnlock(file: file, user: user, rawKey: rawKey, username: user.displayName ?? CryptoService.normalizedUsername(username))
            clearAuthenticationFailures(for: identifier)
            recordSecurityEvent(.loginSucceeded, message: "账户已用密码登录")
            return true
        } catch {
            if unlockWithDecoyPassword(username: username, password: password) {
                clearAuthenticationFailures(for: identifier)
                return true
            }
            registerAuthenticationFailure(for: identifier)
            errorMessage = (error as? VaultError)?.localizedDescription ?? "无法登录"
            return false
        }
    }

    @discardableResult
    func unlock(userID: UUID, password: String) -> Bool {
        let identifier = "userID:\(userID.uuidString)"
        guard canAttemptAuthentication(identifier) else { return false }
        do {
            let file = try readVaultFile()
            guard let user = file.users.first(where: { $0.id == userID }) else {
                throw VaultError.invalidUsername
            }
            let passwordKey = try CryptoService.deriveKey(password: password, salt: user.passwordSalt, rounds: passwordRounds(for: user, in: file))
            let rawKey = try CryptoService.open(user.wrappedVaultKey, using: passwordKey)
            try finishUnlock(file: file, user: user, rawKey: rawKey, username: user.displayName ?? "本地账户")
            clearAuthenticationFailures(for: identifier)
            recordSecurityEvent(.loginSucceeded, message: "账户已用密码登录")
            return true
        } catch {
            if unlockWithDecoyPassword(userID: userID, password: password) {
                clearAuthenticationFailures(for: identifier)
                return true
            }
            registerAuthenticationFailure(for: identifier)
            errorMessage = (error as? VaultError)?.localizedDescription ?? "无法登录"
            return false
        }
    }

    var currentAccountAdvancedDataProtectionEnabled: Bool {
        isAdvancedDataProtectionEnabled(userID: currentUserID)
    }

    var currentAccountID: UUID? {
        currentUserID
    }

    var vaultStoragePath: String {
        vaultURL.deletingLastPathComponent().path
    }

    var vaultFileUpdatedAt: Date? {
        vaultFile?.updatedAt
    }

    var encryptedVaultByteCount: Int {
        vaultItems.reduce(0) { $0 + $1.byteCount }
    }

    func isAdvancedDataProtectionEnabled(userID: UUID?) -> Bool {
        guard let userID else { return false }
        if let user = vaultFile?.users.first(where: { $0.id == userID }) { return user.advancedDataProtectionEnabled }
        return accounts.first(where: { $0.id == userID })?.advancedDataProtectionEnabled == true
    }

    func setAdvancedDataProtectionForCurrentAccount(_ enabled: Bool) {
        guard let currentUserID else { return }
        setAdvancedDataProtectionEnabled(enabled, for: currentUserID)
    }

    var currentAccountDecoyPasswordEnabled: Bool {
        guard let currentUserID else { return false }
        if let user = vaultFile?.users.first(where: { $0.id == currentUserID }) {
            return user.decoyPasswordSalt != nil && user.decoyPasswordVerifier != nil
        }
        return false
    }

    var currentAccountDecoyPasswordAction: DecoyPasswordAction {
        guard let currentUserID,
              let user = vaultFile?.users.first(where: { $0.id == currentUserID }) else {
            return .openDecoySpace
        }
        return user.decoyPasswordAction
    }

    func setDecoyPasswordForCurrentAccount(currentPassword: String, decoyPassword: String, confirmation: String, action: DecoyPasswordAction) {
        guard currentAccountAdvancedDataProtectionEnabled else {
            errorMessage = "请先开启最高保护模式，再设置虚假密码"
            return
        }
        guard decoyPassword == confirmation else {
            errorMessage = "两次输入的虚假密码不一致"
            return
        }
        guard !decoyPassword.isEmpty else {
            errorMessage = "虚假密码不能为空"
            return
        }
        do {
            var file = try readVaultFile()
            try validateCurrentUserPassword(currentPassword, against: file)
            guard let currentUserID,
                  let index = file.users.firstIndex(where: { $0.id == currentUserID }) else {
                throw VaultError.invalidUsername
            }
            let user = file.users[index]
            let realKey = try CryptoService.deriveKey(password: decoyPassword, salt: user.passwordSalt, rounds: passwordRounds(for: user, in: file))
            if (try? CryptoService.open(user.wrappedVaultKey, using: realKey)) != nil {
                errorMessage = "虚假密码不能和真实密码相同"
                return
            }
            let salt = try CryptoService.randomData(count: 16)
            let verifier = try Self.decoyVerifier(password: decoyPassword, salt: salt, rounds: file.rounds)
            file.users[index].decoyPasswordSalt = salt
            file.users[index].decoyPasswordVerifier = verifier
            file.users[index].decoyPasswordAction = action
            file.users[index].advancedDataProtectionEnabled = true
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            vaultFile = file
            refreshAccounts(from: file)
            autoLockMinutes = 1
            recordSecurityEvent(.decoyPasswordConfigured, message: action == .openDecoySpace ? "虚假密码已设置为进入虚假空间" : "虚假密码已设置为销毁本地数据")
            errorMessage = "虚假密码已设置"
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "设置虚假密码失败"
        }
    }

    func disableDecoyPasswordForCurrentAccount(currentPassword: String, confirmationText: String) {
        guard confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "关闭虚假密码" else {
            errorMessage = "请输入“关闭虚假密码”以确认"
            return
        }
        do {
            var file = try readVaultFile()
            try validateCurrentUserPassword(currentPassword, against: file)
            guard let currentUserID,
                  let index = file.users.firstIndex(where: { $0.id == currentUserID }) else {
                throw VaultError.invalidUsername
            }
            file.users[index].decoyPasswordSalt = nil
            file.users[index].decoyPasswordVerifier = nil
            file.users[index].decoyPasswordAction = .openDecoySpace
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            vaultFile = file
            refreshAccounts(from: file)
            recordSecurityEvent(.decoyPasswordDisabled, message: "虚假密码已关闭")
            errorMessage = "虚假密码已关闭"
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "关闭虚假密码失败"
        }
    }

    private func setAdvancedDataProtectionEnabled(_ enabled: Bool, for userID: UUID) {
        do {
            var file = try readVaultFile()
            guard let index = file.users.firstIndex(where: { $0.id == userID }) else { return }
            if !enabled,
               file.users[index].decoyPasswordSalt != nil || file.users[index].decoyPasswordVerifier != nil {
                errorMessage = "请先关闭虚假密码，再关闭最高保护模式"
                return
            }
            file.users[index].advancedDataProtectionEnabled = enabled
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            vaultFile = file
            refreshAccounts(from: file)
            if currentUserID == userID, enabled {
                autoLockMinutes = 1
                imagePreviewCache.removeAll(keepingCapacity: false)
            }
            if currentUserID == userID {
                recordSecurityEvent(enabled ? .advancedProtectionEnabled : .advancedProtectionDisabled, message: enabled ? "复制、导出、共享和预览已限制" : "高级数据保护已关闭")
            }
            errorMessage = enabled ? "高级数据保护已开启：预览已隐藏，自动锁定已收紧到 1 分钟" : "高级数据保护已关闭"
        } catch {
            errorMessage = "更新高级数据保护失败：\(error.localizedDescription)"
        }
    }

    func rotateRecoveryCode() {
        guard let vaultKey, var file = vaultFile, let currentUserID else { return }
        do {
            guard let index = file.users.firstIndex(where: { $0.id == currentUserID }) else { throw VaultError.corruptVault }
            let recovery = try makeRecoveryWrap(for: vaultKey)
            file.users[index].recoverySalt = recovery.salt
            file.users[index].recoveryWrappedVaultKey = recovery.wrappedVaultKey
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            vaultFile = file
            recoveryCodeToShow = recovery.code
            recordSecurityEvent(.recoveryCodeGenerated, message: "当前账户生成了新的恢复码")
            errorMessage = nil
        } catch {
            errorMessage = "生成恢复码失败：\(error.localizedDescription)"
        }
    }

    func dismissRecoveryCode() {
        recoveryCodeToShow = nil
    }

    @discardableResult
    func blockAdvancedProtectionAction(_ message: String) -> Bool {
        guard currentAccountAdvancedDataProtectionEnabled else { return false }
        errorMessage = message
        recordSecurityEvent(.protectedActionBlocked, result: .blocked, message: message)
        return true
    }

    func recordSecurityEvent(_ eventType: SecurityLogEventType, result: SecurityLogResult = .success, message: String) {
        guard state == .unlocked, vaultKey != nil, currentUserID != nil else { return }
        if let latest = securityLogs.first,
           latest.eventType == eventType,
           latest.result == result,
           latest.message == Self.sanitizedLogMessage(message),
           Date().timeIntervalSince(latest.timestamp) < 5 {
            return
        }
        let entry = SecurityLogEntry(
            eventType: eventType,
            result: result,
            accountName: signedInUsername ?? "本地账户",
            message: Self.sanitizedLogMessage(message)
        )
        securityLogs.insert(entry, at: 0)
        if securityLogs.count > Self.maxSecurityLogEntries {
            securityLogs = Array(securityLogs.prefix(Self.maxSecurityLogEntries))
        }
        persist()
    }

    func clearSecurityLogs(currentPassword: String, confirmationText: String) {
        guard confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "清空安全日志" else {
            errorMessage = "请输入“清空安全日志”以确认"
            return
        }
        do {
            let file = try readVaultFile()
            try validateCurrentUserPassword(currentPassword, against: file)
            securityLogs.removeAll(keepingCapacity: false)
            securityLogs.append(SecurityLogEntry(
                eventType: .securityLogsCleared,
                result: .success,
                accountName: signedInUsername ?? "本地账户",
                message: "安全日志已清空"
            ))
            persist()
            errorMessage = "安全日志已清空"
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "清空安全日志失败"
        }
    }

    func exportEncryptedSecurityAudit(to destinationURL: URL, currentPassword: String, confirmationText: String) {
        guard confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "导出安全日志" else {
            errorMessage = "请输入“导出安全日志”以确认"
            return
        }
        do {
            let file = try readVaultFile()
            try validateCurrentUserPassword(currentPassword, against: file)
            let salt = try CryptoService.randomData(count: 16)
            let key = try CryptoService.deriveKey(password: currentPassword, salt: salt, rounds: CryptoService.defaultRounds)
            let package = EncryptedSecurityAuditPackage(
                version: 1,
                salt: salt,
                rounds: CryptoService.defaultRounds,
                encryptedLogs: try CryptoService.seal(try JSONEncoder().encode(securityLogs), using: key),
                createdAt: .now
            )
            try JSONEncoder().encode(package).write(to: destinationURL, options: [.atomic])
            errorMessage = "加密安全日志已导出"
        } catch {
            errorMessage = "导出安全日志失败：\(error.localizedDescription)"
        }
    }

    func exportSharedNote(id: UUID, sharePassword: String) -> Data? {
        if blockAdvancedProtectionAction("高级数据保护已开启，共享导出已阻止") { return nil }
        guard !sharePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "共享密码不能为空"
            return nil
        }
        guard let note = notes.first(where: { $0.id == id }) else {
            errorMessage = "请选择一条要共享的笔记"
            return nil
        }
        do {
            guard let vaultKey, let currentUserID else { throw VaultError.corruptVault }
            let payload = SharedNotePayload(
                title: note.title,
                body: note.body,
                senderUsername: signedInUsername,
                originalCreatedAt: note.createdAt,
                sharedAt: .now,
                attachments: try sharedAttachments(for: note, userID: currentUserID, rawKey: vaultKey)
            )
            let salt = try CryptoService.randomData(count: 16)
            let key = try CryptoService.deriveKey(password: sharePassword, salt: salt, rounds: CryptoService.defaultRounds)
            let package = SharedNotePackage(
                version: Self.sharedNoteVersion,
                salt: salt,
                rounds: CryptoService.defaultRounds,
                encryptedPayload: try CryptoService.seal(try JSONEncoder().encode(payload), using: key),
                createdAt: .now
            )
            recordSecurityEvent(.sharedNoteExported, message: "已导出 1 条共享笔记")
            return try JSONEncoder().encode(package)
        } catch {
            errorMessage = "导出共享文件失败：\(error.localizedDescription)"
            recordSecurityEvent(.sharedNoteExported, result: .failure, message: "共享笔记导出失败")
            return nil
        }
    }

    @discardableResult
    func importSharedNote(data: Data, sharePassword: String) -> UUID? {
        if blockAdvancedProtectionAction("高级数据保护已开启，共享导入已阻止") { return nil }
        guard !sharePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "共享密码不能为空"
            return nil
        }
        guard data.count <= Self.maxSharedPackageBytes else {
            errorMessage = "共享文件过大，无法导入"
            return nil
        }
        do {
            let package = try JSONDecoder().decode(SharedNotePackage.self, from: data)
            guard package.version == Self.sharedNoteVersion else { throw VaultError.corruptVault }
            let key = try CryptoService.deriveKey(password: sharePassword, salt: package.salt, rounds: package.rounds)
            let plaintext = try CryptoService.open(package.encryptedPayload, using: key)
            let payload = try JSONDecoder().decode(SharedNotePayload.self, from: plaintext)
            var title = payload.title.isEmpty ? "共享笔记" : payload.title
            title = "共享：\(title)"
            let prefix = payload.senderUsername.map { "来自 \($0)\n\n" } ?? ""
            guard let vaultKey, let currentUserID else { throw VaultError.corruptVault }
            guard payload.attachments.count <= Self.maxSharedAttachments else { throw VaultError.corruptVault }
            var attachments: [VaultAttachment] = []
            var totalAttachmentBytes = 0
            do {
                for sharedAttachment in payload.attachments {
                    guard sharedAttachment.byteCount >= 0,
                          sharedAttachment.byteCount == sharedAttachment.data.count,
                          sharedAttachment.byteCount <= Self.maxSharedAttachmentBytes,
                          totalAttachmentBytes <= Self.maxSharedTotalAttachmentBytes - sharedAttachment.byteCount else {
                        throw VaultError.corruptVault
                    }
                    totalAttachmentBytes += sharedAttachment.byteCount
                    let attachment = VaultAttachment(
                        fileName: sharedAttachment.fileName,
                        contentType: sharedAttachment.contentType,
                        byteCount: sharedAttachment.data.count
                    )
                    try writeAttachmentData(sharedAttachment.data, for: attachment.id, userID: currentUserID, rawKey: vaultKey)
                    attachments.append(attachment)
                }
            } catch {
                attachments.forEach { try? removeAttachmentBlob(id: $0.id, userID: currentUserID) }
                throw error
            }
            let note = Note(title: title, body: "\(prefix)\(payload.body)", attachments: attachments, createdAt: payload.originalCreatedAt, updatedAt: .now)
            notes.insert(note, at: 0)
            persist()
            touchActivity()
            errorMessage = "共享笔记已导入"
            recordSecurityEvent(.sharedNoteImported, message: "已导入 1 条共享笔记")
            return note.id
        } catch {
            errorMessage = "导入失败：共享密码不正确，或文件不是有效的密笺共享文件"
            recordSecurityEvent(.sharedNoteImported, result: .failure, message: "共享笔记导入失败")
            return nil
        }
    }

    func lock() {
        guard state == .unlocked else { return }
        cancelAllVaultImportJobs()
        recordSecurityEvent(.locked, message: "账户已锁定")
        notes.removeAll(keepingCapacity: false)
        vaultItems.removeAll(keepingCapacity: false)
        securityLogs.removeAll(keepingCapacity: false)
        clearSensitivePreviewCaches()
        let keyByteCount = vaultKey?.count ?? 0
        vaultKey?.resetBytes(in: 0..<keyByteCount)
        vaultKey = nil
        vaultFile = nil
        currentUserID = nil
        signedInUsername = nil
        isDecoySession = false
        state = .locked
        errorMessage = nil
    }

    func addNote() -> UUID {
        let note = Note()
        notes.insert(note, at: 0)
        persist()
        touchActivity()
        return note.id
    }

    @discardableResult
    func duplicateNote(id: UUID) -> UUID? {
        guard let source = notes.first(where: { $0.id == id }) else { return nil }
        guard let currentUserID else { return nil }
        do {
            var copiedAttachments: [VaultAttachment] = []
            for attachment in source.attachments {
                var copy = attachment
                copy.id = UUID()
                copy.createdAt = .now
                try copyAttachmentBlob(from: attachment.id, to: copy.id, userID: currentUserID)
                copiedAttachments.append(copy)
            }
            let title = source.title.isEmpty ? "无标题副本" : "\(source.title) 副本"
            let note = Note(
                title: title,
                body: source.body,
                attachments: copiedAttachments,
                tags: source.tags,
                isFavorite: source.isFavorite,
                createdAt: .now,
                updatedAt: .now
            )
            notes.insert(note, at: 0)
            persist()
            touchActivity()
            return note.id
        } catch {
            errorMessage = "复制笔记失败：\(error.localizedDescription)"
            return nil
        }
    }

    func updateNote(id: UUID, title: String? = nil, body: String? = nil, tags: [String]? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if let title, notes[index].title != title {
            notes[index].title = title
            changed = true
        }
        if let body, notes[index].body != body {
            notes[index].body = body
            changed = true
        }
        if let tags {
            let cleaned = Self.cleanedTags(tags)
            if notes[index].tags != cleaned {
                notes[index].tags = cleaned
                changed = true
            }
        }
        guard changed else { return }
        notes[index].updatedAt = .now
        persist()
        touchActivity()
    }

    func togglePinned(noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].isPinned.toggle()
        notes[index].updatedAt = .now
        persist()
        touchActivity()
        errorMessage = notes[index].isPinned ? "已置顶" : "已取消置顶"
    }

    func toggleFavorite(noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].isFavorite.toggle()
        notes[index].updatedAt = .now
        persist()
        touchActivity()
        errorMessage = notes[index].isFavorite ? "已加入收藏" : "已取消收藏"
    }

    func toggleArchived(noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].isArchived.toggle()
        notes[index].updatedAt = .now
        persist()
        touchActivity()
        errorMessage = notes[index].isArchived ? "已归档" : "已移回笔记列表"
    }

    func updateTags(noteID: UUID, tags: [String]) {
        updateNote(id: noteID, tags: tags)
    }

    nonisolated private static func cleanedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func importFilesToVault(urls: [URL], deleteOriginals: Bool = true) {
        guard !urls.isEmpty else { return }
        guard let vaultKey, let currentUserID else {
            errorMessage = "请先解锁保险柜"
            return
        }
        let sourceURLs = urls
        let vaultURL = vaultURL
        let importJobs = beginVaultImportJobs(for: sourceURLs)
        let shouldImportInBackground = sourceURLs.contains { url in
            ((try? Self.fileByteCount(at: url)) ?? Self.backgroundImportThresholdBytes) >= Self.backgroundImportThresholdBytes
        }
        if !shouldImportInBackground {
            var importedItems: [VaultAttachment] = []
            var sourceURLsToDelete: [URL] = []
            do {
                for (url, job) in zip(sourceURLs, importJobs) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let byteCount = try Self.fileByteCount(at: url)
                    let item = VaultAttachment(
                        fileName: Self.sanitizedFileName(url.lastPathComponent),
                        contentType: Self.contentType(for: url),
                        byteCount: byteCount
                    )
                    let token = vaultImportCancellationTokens[job.id]
                    try Self.writeAttachmentFile(from: url, for: item.id, userID: currentUserID, rawKey: vaultKey, byteCount: byteCount, vaultURL: vaultURL, shouldCancel: {
                        token?.isCancelled == true
                    }, waitIfPaused: {
                        token?.waitIfPaused()
                    }) { processed in
                        Task { @MainActor in
                            self.updateVaultImportJob(id: job.id, processedByteCount: processed)
                        }
                    }
                    finishVaultImportJob(id: job.id, status: .finished)
                    importedItems.append(item)
                    sourceURLsToDelete.append(url)
                }
                vaultItems.insert(contentsOf: importedItems, at: 0)
                persist()
                touchActivity()

                var deleteFailures = 0
                if deleteOriginals {
                    for url in sourceURLsToDelete {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        do { try FileManager.default.removeItem(at: url) } catch { deleteFailures += 1 }
                    }
                }
                if deleteOriginals && deleteFailures > 0 {
                    errorMessage = "文件已加密进入保险柜，但有 \(deleteFailures) 个原文件未能删除，请手动确认。"
                } else {
                    errorMessage = importedItems.count == 1 ? "已移入保险柜，原文件已删除" : "已移入 \(importedItems.count) 个文件，原文件已删除"
                }
                recordSecurityEvent(.vaultFilesImported, message: "已加密移入 \(importedItems.count) 个保险柜文件")
            } catch {
                let status: VaultImportJobStatus
                if case .importCancelled = error as? VaultError {
                    status = .cancelled
                } else {
                    status = .failed
                }
                importJobs.forEach { finishVaultImportJob(id: $0.id, status: status) }
                importedItems.forEach { try? Self.removeAttachmentBlob(id: $0.id, userID: currentUserID, vaultURL: vaultURL) }
                if status == .cancelled {
                    errorMessage = "保险柜导入已取消"
                    recordSecurityEvent(.vaultFilesImported, result: .blocked, message: "保险柜文件导入已取消")
                } else {
                    errorMessage = "移入保险柜失败：\(error.localizedDescription)"
                    recordSecurityEvent(.vaultFilesImported, result: .failure, message: "保险柜文件导入失败")
                }
            }
            return
        }

        errorMessage = sourceURLs.count == 1 ? "大文件正在后台加密移入保险柜" : "\(sourceURLs.count) 个大文件正在后台加密移入保险柜"
        Task.detached(priority: .utility) {
            var importedItems: [VaultAttachment] = []
            var sourceURLsToDelete: [URL] = []
            do {
                for (url, job) in zip(sourceURLs, importJobs) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let byteCount = try Self.fileByteCount(at: url)
                    let item = VaultAttachment(
                        fileName: Self.sanitizedFileName(url.lastPathComponent),
                        contentType: Self.contentType(for: url),
                        byteCount: byteCount
                    )
                    let token = await MainActor.run {
                        self.vaultImportCancellationTokens[job.id]
                    }
                    try Self.writeAttachmentFile(from: url, for: item.id, userID: currentUserID, rawKey: vaultKey, byteCount: byteCount, vaultURL: vaultURL, shouldCancel: {
                        token?.isCancelled == true
                    }, waitIfPaused: {
                        token?.waitIfPaused()
                    }) { processed in
                        Task { @MainActor in
                            self.updateVaultImportJob(id: job.id, processedByteCount: processed)
                        }
                    }
                    await MainActor.run {
                        self.finishVaultImportJob(id: job.id, status: .finished)
                    }
                    importedItems.append(item)
                    sourceURLsToDelete.append(url)
                }

                let accepted = await MainActor.run {
                    guard self.state == .unlocked, self.currentUserID == currentUserID else { return false }
                    self.vaultItems.insert(contentsOf: importedItems, at: 0)
                    self.persist()
                    self.touchActivity()
                    return true
                }
                guard accepted else {
                    for item in importedItems {
                        try? Self.removeAttachmentBlob(id: item.id, userID: currentUserID, vaultURL: vaultURL)
                    }
                    await MainActor.run {
                        importJobs.forEach { self.finishVaultImportJob(id: $0.id, status: .cancelled) }
                    }
                    return
                }

                var deleteFailures = 0
                if deleteOriginals {
                    for url in sourceURLsToDelete {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        do { try FileManager.default.removeItem(at: url) } catch { deleteFailures += 1 }
                    }
                }
                await MainActor.run {
                    if deleteOriginals && deleteFailures > 0 {
                        self.errorMessage = "文件已加密进入保险柜，但有 \(deleteFailures) 个原文件未能删除，请手动确认。"
                    } else {
                        self.errorMessage = importedItems.count == 1 ? "已移入保险柜，原文件已删除" : "已移入 \(importedItems.count) 个文件，原文件已删除"
                    }
                    self.recordSecurityEvent(.vaultFilesImported, message: "已加密移入 \(importedItems.count) 个保险柜文件")
                }
            } catch {
                for item in importedItems {
                    try? Self.removeAttachmentBlob(id: item.id, userID: currentUserID, vaultURL: vaultURL)
                }
                await MainActor.run {
                    let status: VaultImportJobStatus
                    if case .importCancelled = error as? VaultError {
                        status = .cancelled
                    } else {
                        status = .failed
                    }
                    importJobs.forEach { self.finishVaultImportJob(id: $0.id, status: status) }
                    if status == .cancelled {
                        self.errorMessage = "保险柜导入已取消"
                        self.recordSecurityEvent(.vaultFilesImported, result: .blocked, message: "保险柜文件导入已取消")
                    } else {
                        self.errorMessage = "移入保险柜失败：\(error.localizedDescription)"
                        self.recordSecurityEvent(.vaultFilesImported, result: .failure, message: "保险柜文件导入失败")
                    }
                }
            }
        }
    }

    func cancelVaultImportJob(id: UUID) {
        vaultImportCancellationTokens[id]?.cancel()
        guard let index = vaultImportJobs.firstIndex(where: { $0.id == id }),
              vaultImportJobs[index].status == .encrypting || vaultImportJobs[index].status == .paused else { return }
        vaultImportJobs[index].status = .cancelling
        vaultImportJobs[index].updatedAt = .now
    }

    func pauseVaultImportJob(id: UUID) {
        guard let index = vaultImportJobs.firstIndex(where: { $0.id == id }),
              vaultImportJobs[index].status == .encrypting else { return }
        vaultImportCancellationTokens[id]?.pause()
        vaultImportJobs[index].status = .paused
        vaultImportJobs[index].updatedAt = .now
    }

    func resumeVaultImportJob(id: UUID) {
        guard let index = vaultImportJobs.firstIndex(where: { $0.id == id }),
              vaultImportJobs[index].status == .paused else { return }
        vaultImportCancellationTokens[id]?.resume()
        vaultImportJobs[index].status = .encrypting
        vaultImportJobs[index].updatedAt = .now
    }

    func clearFinishedVaultImportJobs() {
        vaultImportJobs.removeAll { !$0.isActive }
    }

    private func cancelAllVaultImportJobs() {
        for id in vaultImportCancellationTokens.keys {
            vaultImportCancellationTokens[id]?.cancel()
        }
        for index in vaultImportJobs.indices where vaultImportJobs[index].isActive {
            vaultImportJobs[index].status = .cancelling
            vaultImportJobs[index].updatedAt = .now
        }
    }

    private func beginVaultImportJobs(for urls: [URL]) -> [VaultImportJob] {
        let jobs = urls.map { url in
            VaultImportJob(
                id: UUID(),
                fileName: Self.sanitizedFileName(url.lastPathComponent),
                byteCount: (try? Self.fileByteCount(at: url)) ?? 0,
                processedByteCount: 0,
                status: .encrypting,
                startedAt: .now,
                updatedAt: .now
            )
        }
        for job in jobs {
            vaultImportCancellationTokens[job.id] = VaultImportCancellationToken()
        }
        vaultImportJobs.insert(contentsOf: jobs, at: 0)
        vaultImportJobs = Array(vaultImportJobs.prefix(12))
        return jobs
    }

    private func updateVaultImportJob(id: UUID, processedByteCount: Int) {
        guard let index = vaultImportJobs.firstIndex(where: { $0.id == id }) else { return }
        vaultImportJobs[index].processedByteCount = processedByteCount
        vaultImportJobs[index].updatedAt = .now
    }

    private func finishVaultImportJob(id: UUID, status: VaultImportJobStatus) {
        guard let index = vaultImportJobs.firstIndex(where: { $0.id == id }) else { return }
        vaultImportJobs[index].status = status
        vaultImportJobs[index].updatedAt = .now
        vaultImportCancellationTokens[id] = nil
        if status == .finished {
            vaultImportJobs[index].processedByteCount = vaultImportJobs[index].byteCount
        }
    }

    func vaultItemData(itemID: UUID) -> Data? {
        if currentAccountAdvancedDataProtectionEnabled {
            _ = blockAdvancedProtectionAction("高级数据保护已开启，保险柜文件读取已阻止")
            return nil
        }
        guard vaultItems.contains(where: { $0.id == itemID }), let vaultKey, let currentUserID else { return nil }
        do {
            return try readAttachmentData(id: itemID, userID: currentUserID, rawKey: vaultKey)
        } catch {
            errorMessage = "读取保险柜文件失败：\(error.localizedDescription)"
            return nil
        }
    }

    func internalVaultPreviewData(itemID: UUID) -> Data? {
        guard vaultItems.contains(where: { $0.id == itemID }), let vaultKey, let currentUserID else { return nil }
        do {
            let data = try readAttachmentData(id: itemID, userID: currentUserID, rawKey: vaultKey)
            removePreviewCacheEntry(for: itemID)
            recordSecurityEvent(.vaultFileViewed, message: "已在应用内查看 1 个保险柜文件")
            return data
        } catch {
            errorMessage = "读取保险柜文件失败：\(error.localizedDescription)"
            recordSecurityEvent(.vaultFileViewed, result: .failure, message: "保险柜文件内部查看失败")
            return nil
        }
    }

    func clearSensitivePreviewCaches(recordEvent: Bool = false) {
        let hadPreviewCache = !imagePreviewCache.isEmpty
        imagePreviewCache.removeAll(keepingCapacity: false)
        previewCacheCost = 0
        if recordEvent && hadPreviewCache {
            recordSecurityEvent(.protectedActionBlocked, message: "锁定时已清理保险柜预览缓存")
        }
    }

    func exportVaultItem(itemID: UUID, to destinationURL: URL) {
        if blockAdvancedProtectionAction("高级数据保护已开启，保险柜文件导出已阻止") { return }
        guard vaultItems.contains(where: { $0.id == itemID }), let vaultKey, let currentUserID else { return }
        let accessing = destinationURL.startAccessingSecurityScopedResource()
        defer { if accessing { destinationURL.stopAccessingSecurityScopedResource() } }
        do {
            try streamAttachmentData(id: itemID, userID: currentUserID, rawKey: vaultKey, to: destinationURL)
            errorMessage = "文件已导出"
            recordSecurityEvent(.vaultFileExported, message: "已导出 1 个保险柜文件")
        } catch {
            errorMessage = "导出文件失败：\(error.localizedDescription)"
            recordSecurityEvent(.vaultFileExported, result: .failure, message: "保险柜文件导出失败")
        }
    }

    func makeVaultMediaResource(itemID: UUID) -> VaultMediaResource? {
        guard let item = vaultItems.first(where: { $0.id == itemID }),
              let vaultKey,
              let currentUserID else { return nil }
        do {
            let reader = try EncryptedAttachmentReader(
                url: attachmentURL(for: itemID, userID: currentUserID),
                rawKey: vaultKey,
                magic: Self.attachmentMagic,
                maximumEncryptedChunkSize: Self.maxEncryptedAttachmentChunkSize,
                encryptedChunkOverhead: Self.attachmentChunkOverhead
            )
            guard reader.byteCount == item.byteCount else { throw VaultError.corruptVault }
            recordSecurityEvent(.vaultFileViewed, message: "已在应用内查看 1 个保险柜文件")
            return VaultMediaResource(
                id: item.id,
                fileName: item.fileName,
                contentType: item.contentType,
                byteCount: item.byteCount,
                reader: reader
            )
        } catch {
            errorMessage = "读取保险柜文件失败：\(error.localizedDescription)"
            recordSecurityEvent(.vaultFileViewed, result: .failure, message: "保险柜文件内部查看失败")
            return nil
        }
    }

    func previewVaultImage(itemID: UUID) async -> NSImage? {
        guard !currentAccountAdvancedDataProtectionEnabled else { return nil }
        if var cached = imagePreviewCache[itemID] {
            previewCacheClock &+= 1
            cached.lastAccess = previewCacheClock
            imagePreviewCache[itemID] = cached
            return cached.image
        }
        guard let item = vaultItems.first(where: { $0.id == itemID }),
              item.contentType?.hasPrefix("image/") == true,
              item.byteCount <= Self.maxPreviewSourceBytes,
              let vaultKey,
              let currentUserID else { return nil }
        let url = attachmentURL(for: itemID, userID: currentUserID)
        let imageBox = await Task.detached(priority: .utility) {
            do {
                let reader = try EncryptedAttachmentReader(
                    url: url,
                    rawKey: vaultKey,
                    magic: Self.attachmentMagic,
                    maximumEncryptedChunkSize: Self.maxEncryptedAttachmentChunkSize,
                    encryptedChunkOverhead: Self.attachmentChunkOverhead
                )
                let data = try reader.readAll(maximumBytes: Self.maxPreviewSourceBytes)
                return Self.downsampledImage(data: data, maximumPixelSize: 560).map(SendableNSImage.init)
            } catch {
                return nil
            }
        }.value
        let image = imageBox?.image
        if let image { insertPreviewImage(image, for: itemID) }
        return image
    }

    nonisolated private static func downsampledImage(data: Data, maximumPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func insertPreviewImage(_ image: NSImage, for itemID: UUID) {
        previewCacheCost = imagePreviewCache.values.reduce(0) { $0 + $1.cost }
        removePreviewCacheEntry(for: itemID)
        previewCacheClock &+= 1
        let pixels = image.representations.first.map { max(1, $0.pixelsWide) * max(1, $0.pixelsHigh) } ?? 1
        let entry = PreviewCacheEntry(image: image, cost: pixels * 4, lastAccess: previewCacheClock)
        imagePreviewCache[itemID] = entry
        previewCacheCost += entry.cost
        while imagePreviewCache.count > Self.maxPreviewCacheItems || previewCacheCost > Self.maxPreviewCacheCost {
            guard let oldest = imagePreviewCache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            removePreviewCacheEntry(for: oldest.key)
        }
    }

    private func removePreviewCacheEntry(for itemID: UUID) {
        if let removed = imagePreviewCache.removeValue(forKey: itemID) {
            previewCacheCost = max(0, previewCacheCost - removed.cost)
        }
    }

    func deleteVaultItem(itemID: UUID) {
        guard let currentUserID,
              let item = vaultItems.first(where: { $0.id == itemID }),
              !vaultDeletingItemIDs.contains(itemID) else { return }
        let url = attachmentURL(for: itemID, userID: currentUserID)
        if item.byteCount < Self.backgroundImportThresholdBytes {
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                vaultItems.removeAll { $0.id == itemID }
                removePreviewCacheEntry(for: itemID)
                persist()
                touchActivity()
                errorMessage = "文件已从保险柜删除"
                recordSecurityEvent(.vaultFileDeleted, message: "已删除 1 个保险柜文件")
            } catch {
                errorMessage = "删除保险柜文件失败：\(error.localizedDescription)"
            }
            return
        }
        vaultDeletingItemIDs.insert(itemID)
        Task.detached(priority: .utility) {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                await MainActor.run {
                    guard self.currentUserID == currentUserID else { return }
                    self.vaultItems.removeAll { $0.id == itemID }
                    self.removePreviewCacheEntry(for: itemID)
                    self.vaultDeletingItemIDs.remove(itemID)
                    self.persist()
                    self.touchActivity()
                    self.errorMessage = "文件已从保险柜删除"
                    self.recordSecurityEvent(.vaultFileDeleted, message: "已删除 1 个保险柜文件")
                }
            } catch {
                await MainActor.run {
                    self.vaultDeletingItemIDs.remove(itemID)
                    self.errorMessage = "删除保险柜文件失败：\(error.localizedDescription)"
                    self.recordSecurityEvent(.vaultFileDeleted, result: .failure, message: "保险柜文件删除失败")
                }
            }
        }
    }

    func deleteNotes(at offsets: IndexSet) {
        guard let currentUserID else { return }
        var removedAny = false
        for index in offsets.sorted(by: >) where notes.indices.contains(index) {
            do {
                try removeAttachmentFiles(in: notes[index], userID: currentUserID)
                notes.remove(at: index)
                removedAny = true
            } catch {
                errorMessage = "删除笔记附件失败：\(error.localizedDescription)"
            }
        }
        if removedAny {
            persist()
            touchActivity()
        }
    }

    func deleteNote(id: UUID) {
        if let currentUserID, let note = notes.first(where: { $0.id == id }) {
            do {
                try removeAttachmentFiles(in: note, userID: currentUserID)
            } catch {
                errorMessage = "删除笔记附件失败：\(error.localizedDescription)"
                return
            }
        }
        notes.removeAll { $0.id == id }
        persist()
        touchActivity()
    }

    func deleteCurrentUser(password: String, confirmationText: String) {
        guard confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "删除我的账户" else {
            errorMessage = "请输入“删除我的账户”以确认"
            return
        }
        guard let currentUserID else { return }
        do {
            var file = try readVaultFile()
            try validateCurrentUserPassword(password, against: file)
            guard let index = file.users.firstIndex(where: { $0.id == currentUserID }) else {
                throw VaultError.invalidUsername
            }
            let userAttachments = attachmentDirectory(for: currentUserID)
            if FileManager.default.fileExists(atPath: userAttachments.path) {
                try FileManager.default.removeItem(at: userAttachments)
            }
            file.users.remove(at: index)
            file.updatedAt = .now
            try write(file)
            refreshAccounts(from: file)
            userCount = file.users.count
            vaultFile = file

            notes.removeAll(keepingCapacity: false)
            vaultItems.removeAll(keepingCapacity: false)
            imagePreviewCache.removeAll(keepingCapacity: false)
            let keyByteCount = vaultKey?.count ?? 0
            vaultKey?.resetBytes(in: 0..<keyByteCount)
            vaultKey = nil
            self.currentUserID = nil
            signedInUsername = nil
            state = file.users.isEmpty ? .needsAdminSetup : .locked
            errorMessage = "当前账户已删除，相关加密数据已销毁"
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "删除账户失败"
        }
    }

    private func sharedAttachments(for note: Note, userID: UUID, rawKey: Data) throws -> [SharedAttachmentPayload] {
        guard note.attachments.count <= Self.maxSharedAttachments else { throw VaultError.corruptVault }
        var totalBytes = 0
        return try note.attachments.map { attachment in
            let data = try readAttachmentData(id: attachment.id, userID: userID, rawKey: rawKey)
            guard data.count <= Self.maxSharedAttachmentBytes,
                  totalBytes <= Self.maxSharedTotalAttachmentBytes - data.count else {
                throw VaultError.corruptVault
            }
            totalBytes += data.count
            return SharedAttachmentPayload(
                fileName: attachment.fileName,
                contentType: attachment.contentType,
                byteCount: data.count,
                data: data
            )
        }
    }

    private func writeAttachmentData(_ data: Data, for attachmentID: UUID, userID: UUID, rawKey: Data) throws {
        try FileManager.default.createDirectory(at: attachmentDirectory(for: userID), withIntermediateDirectories: true)
        let url = attachmentURL(for: attachmentID, userID: userID)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }
        try writeAttachmentHeader(to: output, byteCount: data.count)
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.attachmentChunkSize, data.count)
            try writeEncryptedAttachmentChunk(data.subdata(in: offset..<end), to: output, rawKey: rawKey)
            offset = end
        }
    }

    private func readAttachmentData(id attachmentID: UUID, userID: UUID, rawKey: Data) throws -> Data {
        let url = attachmentURL(for: attachmentID, userID: userID)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let prefix = try input.read(upToCount: Self.attachmentMagic.count) ?? Data()
        guard prefix == Self.attachmentMagic else {
            let encrypted = try Data(contentsOf: url)
            return try CryptoService.open(encrypted, using: SymmetricKey(data: rawKey))
        }
        let declaredByteCount = try readUInt64(from: input)
        guard declaredByteCount <= UInt64(Int.max) else { throw VaultError.corruptVault }
        var processedByteCount = 0
        var plaintext = Data()
        while true {
            guard let length = try readUInt32(from: input) else { break }
            guard length > 0, length <= UInt32(Self.maxEncryptedAttachmentChunkSize) else {
                throw VaultError.corruptVault
            }
            let encrypted = try readExactData(from: input, count: Int(length))
            plaintext.append(try CryptoService.open(encrypted, using: SymmetricKey(data: rawKey)))
            processedByteCount += encrypted.count - Self.attachmentChunkOverhead
            guard processedByteCount <= Int(declaredByteCount) else { throw VaultError.corruptVault }
        }
        guard processedByteCount == Int(declaredByteCount) else { throw VaultError.corruptVault }
        return plaintext
    }

    private func writeAttachmentFile(from sourceURL: URL, for attachmentID: UUID, userID: UUID, rawKey: Data, byteCount: Int) throws {
        try FileManager.default.createDirectory(at: attachmentDirectory(for: userID), withIntermediateDirectories: true)
        let destinationURL = attachmentURL(for: attachmentID, userID: userID)
        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }
        try writeAttachmentHeader(to: output, byteCount: byteCount)
        while true {
            let chunk = try input.read(upToCount: Self.attachmentChunkSize) ?? Data()
            if chunk.isEmpty { break }
            try writeEncryptedAttachmentChunk(chunk, to: output, rawKey: rawKey)
        }
    }

    nonisolated private static func writeAttachmentFile(
        from sourceURL: URL,
        for attachmentID: UUID,
        userID: UUID,
        rawKey: Data,
        byteCount: Int,
        vaultURL: URL,
        shouldCancel: @Sendable () -> Bool = { false },
        waitIfPaused: @Sendable () -> Void = {},
        progress: @Sendable (Int) -> Void = { _ in }
    ) throws {
        try FileManager.default.createDirectory(at: attachmentDirectory(for: userID, vaultURL: vaultURL), withIntermediateDirectories: true)
        let destinationURL = attachmentURL(for: attachmentID, userID: userID, vaultURL: vaultURL)
        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }
        try writeAttachmentHeader(to: output, byteCount: byteCount)
        var processedByteCount = 0
        while true {
            waitIfPaused()
            if shouldCancel() {
                try? output.close()
                try? input.close()
                try? FileManager.default.removeItem(at: destinationURL)
                throw VaultError.importCancelled
            }
            let chunk = try input.read(upToCount: attachmentChunkSize) ?? Data()
            if chunk.isEmpty { break }
            try writeEncryptedAttachmentChunk(chunk, to: output, rawKey: rawKey)
            processedByteCount += chunk.count
            progress(processedByteCount)
        }
    }

    private func streamAttachmentData(id attachmentID: UUID, userID: UUID, rawKey: Data, to destinationURL: URL) throws {
        let sourceURL = attachmentURL(for: attachmentID, userID: userID)
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        let prefix = try input.read(upToCount: Self.attachmentMagic.count) ?? Data()
        guard prefix == Self.attachmentMagic else {
            let encrypted = try Data(contentsOf: sourceURL)
            try output.write(contentsOf: try CryptoService.open(encrypted, using: SymmetricKey(data: rawKey)))
            return
        }
        let declaredByteCount = try readUInt64(from: input)
        guard declaredByteCount <= UInt64(Int.max) else { throw VaultError.corruptVault }
        var processedByteCount = 0
        while true {
            guard let length = try readUInt32(from: input) else { break }
            guard length > 0, length <= UInt32(Self.maxEncryptedAttachmentChunkSize) else {
                throw VaultError.corruptVault
            }
            let encrypted = try readExactData(from: input, count: Int(length))
            try output.write(contentsOf: try CryptoService.open(encrypted, using: SymmetricKey(data: rawKey)))
            processedByteCount += encrypted.count - Self.attachmentChunkOverhead
            guard processedByteCount <= Int(declaredByteCount) else { throw VaultError.corruptVault }
        }
        guard processedByteCount == Int(declaredByteCount) else { throw VaultError.corruptVault }
    }

    private func writeAttachmentHeader(to output: FileHandle, byteCount: Int) throws {
        try output.write(contentsOf: Self.attachmentMagic)
        try output.write(contentsOf: littleEndianData(UInt64(byteCount)))
    }

    nonisolated private static func writeAttachmentHeader(to output: FileHandle, byteCount: Int) throws {
        try output.write(contentsOf: attachmentMagic)
        try output.write(contentsOf: littleEndianData(UInt64(byteCount)))
    }

    private func writeEncryptedAttachmentChunk(_ chunk: Data, to output: FileHandle, rawKey: Data) throws {
        let encrypted = try CryptoService.seal(chunk, using: SymmetricKey(data: rawKey))
        try output.write(contentsOf: littleEndianData(UInt32(encrypted.count)))
        try output.write(contentsOf: encrypted)
    }

    nonisolated private static func writeEncryptedAttachmentChunk(_ chunk: Data, to output: FileHandle, rawKey: Data) throws {
        let encrypted = try CryptoService.seal(chunk, using: SymmetricKey(data: rawKey))
        try output.write(contentsOf: littleEndianData(UInt32(encrypted.count)))
        try output.write(contentsOf: encrypted)
    }

    private func readUInt32(from input: FileHandle) throws -> UInt32? {
        guard let data = try input.read(upToCount: 4), !data.isEmpty else { return nil }
        guard data.count == 4 else { throw VaultError.corruptVault }
        return data.enumerated().reduce(UInt32(0)) { result, pair in
            result | (UInt32(pair.element) << UInt32(pair.offset * 8))
        }
    }

    private func readUInt64(from input: FileHandle) throws -> UInt64 {
        let data = try readExactData(from: input, count: 8)
        return data.enumerated().reduce(UInt64(0)) { result, pair in
            result | (UInt64(pair.element) << UInt64(pair.offset * 8))
        }
    }

    private func readExactData(from input: FileHandle, count: Int) throws -> Data {
        let data = try input.read(upToCount: count) ?? Data()
        guard data.count == count else { throw VaultError.corruptVault }
        return data
    }

    private func littleEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndian = value.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<T>.size)
    }

    nonisolated private static func littleEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndian = value.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<T>.size)
    }

    nonisolated private static func fileByteCount(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize { return fileSize }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return Int((attributes[.size] as? NSNumber)?.int64Value ?? 0)
    }

    private func copyAttachmentBlob(from sourceID: UUID, to targetID: UUID, userID: UUID) throws {
        try FileManager.default.createDirectory(at: attachmentDirectory(for: userID), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: attachmentURL(for: sourceID, userID: userID), to: attachmentURL(for: targetID, userID: userID))
    }

    private func removeAttachmentFiles(in note: Note, userID: UUID) throws {
        for attachment in note.attachments {
            try removeAttachmentBlob(id: attachment.id, userID: userID)
        }
    }

    private func removeAttachmentBlob(id attachmentID: UUID, userID: UUID) throws {
        let url = attachmentURL(for: attachmentID, userID: userID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func removeAttachmentBlob(id attachmentID: UUID, userID: UUID, vaultURL: URL) throws {
        let url = attachmentURL(for: attachmentID, userID: userID, vaultURL: vaultURL)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func attachmentURL(for attachmentID: UUID, userID: UUID) -> URL {
        attachmentDirectory(for: userID).appendingPathComponent("\(attachmentID.uuidString).bin")
    }

    nonisolated private static func attachmentURL(for attachmentID: UUID, userID: UUID, vaultURL: URL) -> URL {
        attachmentDirectory(for: userID, vaultURL: vaultURL).appendingPathComponent("\(attachmentID.uuidString).bin")
    }

    private func attachmentDirectory(for userID: UUID) -> URL {
        attachmentsRootURL().appendingPathComponent(userID.uuidString, isDirectory: true)
    }

    nonisolated private static func attachmentDirectory(for userID: UUID, vaultURL: URL) -> URL {
        attachmentsRootURL(vaultURL: vaultURL).appendingPathComponent(userID.uuidString, isDirectory: true)
    }

    private func attachmentsRootURL() -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    }

    private func ensureAttachmentsNeverIndexed() {
        let root = attachmentsRootURL()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let marker = root.appendingPathComponent(".metadata_never_index", isDirectory: false)
            if !FileManager.default.fileExists(atPath: marker.path) {
                FileManager.default.createFile(atPath: marker.path, contents: Data(), attributes: nil)
            }
        } catch {
            errorMessage = "保险柜防索引标记创建失败：\(error.localizedDescription)"
        }
    }

    nonisolated private static func attachmentsRootURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    }

    private func sanitizedFileName(_ value: String) -> String {
        Self.sanitizedFileName(value)
    }

    nonisolated private static func sanitizedFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "保险箱文件" : trimmed
    }

    nonisolated private static func sanitizedLogMessage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "本地安全事件" : trimmed
    }

    nonisolated private static func contentType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    private func makeUser(username: String, displayName: String, password: String, existingVaultKey rawKey: Data, existingEncryptedNotes encryptedNotes: Data) throws -> UserBuild {
        let usernameSalt = try CryptoService.randomData(count: 16)
        let passwordSalt = try CryptoService.randomData(count: 16)
        let passwordKey = try CryptoService.deriveKey(password: password, salt: passwordSalt, rounds: CryptoService.defaultRounds)
        let recovery = try makeRecoveryWrap(for: rawKey)
        let user = UserRecord(
            id: UUID(),
            displayName: displayName,
            usernameSalt: usernameSalt,
            usernameHash: CryptoService.usernameHash(username, salt: usernameSalt),
            passwordSalt: passwordSalt,
            passwordKDF: PasswordKDFConfiguration(rounds: CryptoService.defaultRounds),
            wrappedVaultKey: try CryptoService.seal(rawKey, using: passwordKey),
            recoverySalt: recovery.salt,
            recoveryWrappedVaultKey: recovery.wrappedVaultKey,
            encryptedNotes: encryptedNotes,
            createdAt: .now,
            updatedAt: .now
        )
        return UserBuild(user: user, recoveryCode: recovery.code)
    }

    private func finishUnlock(file: VaultFile, user: UserRecord, rawKey: Data, username: String) throws {
        let payload = try decodePayload(from: user.encryptedNotes, rawKey: rawKey)
        imagePreviewCache.removeAll(keepingCapacity: false)
        notes = payload.notes
        vaultItems = payload.vaultItems
        securityLogs = Array(payload.securityLogs.sorted { $0.timestamp > $1.timestamp }.prefix(Self.maxSecurityLogEntries))
        vaultFile = file
        vaultKey = rawKey
        currentUserID = user.id
        signedInUsername = username
        isDecoySession = false
        refreshAccounts(from: file)
        if user.advancedDataProtectionEnabled {
            autoLockMinutes = min(autoLockMinutes, 1)
        }
        state = .unlocked
        errorMessage = nil
        touchActivity()
    }

    private func finishDecoyUnlock(file: VaultFile, user: UserRecord, decoyKey: Data) throws {
        let payload: VaultPayload
        if let encrypted = user.decoyEncryptedNotes {
            payload = try decodePayload(from: encrypted, rawKey: decoyKey)
        } else {
            payload = VaultPayload(notes: [], vaultItems: [], securityLogs: [])
        }
        imagePreviewCache.removeAll(keepingCapacity: false)
        notes = payload.notes
        vaultItems = payload.vaultItems
        securityLogs = Array(payload.securityLogs.sorted { $0.timestamp > $1.timestamp }.prefix(Self.maxSecurityLogEntries))
        vaultFile = file
        vaultKey = decoyKey
        currentUserID = user.id
        signedInUsername = user.displayName ?? "本地账户"
        isDecoySession = true
        autoLockMinutes = 1
        refreshAccounts(from: file)
        state = .unlocked
        errorMessage = nil
        touchActivity()
    }

    private func unlockWithDecoyPassword(username: String, password: String) -> Bool {
        do {
            let file = try readVaultFile()
            guard let user = try findUser(username: username, in: file) else { return false }
            return handleDecoyPassword(password, user: user, file: file)
        } catch {
            return false
        }
    }

    private func unlockWithDecoyPassword(userID: UUID, password: String) -> Bool {
        do {
            let file = try readVaultFile()
            guard let user = file.users.first(where: { $0.id == userID }) else { return false }
            return handleDecoyPassword(password, user: user, file: file)
        } catch {
            return false
        }
    }

    private func handleDecoyPassword(_ password: String, user: UserRecord, file: VaultFile) -> Bool {
        guard isDecoyPassword(password, for: user, rounds: file.rounds),
              let decoyKey = try? decoyKey(password: password, for: user, rounds: file.rounds) else { return false }
        switch user.decoyPasswordAction {
        case .openDecoySpace:
            do {
                try finishDecoyUnlock(file: file, user: user, decoyKey: decoyKey)
            } catch {
                errorMessage = "虚假空间无法打开"
                return false
            }
        case .eraseLocalData:
            guard destroyLocalVaultAfterDecoyPassword() else { return false }
        }
        return true
    }

    private func isDecoyPassword(_ password: String, for user: UserRecord, rounds: UInt32) -> Bool {
        guard let salt = user.decoyPasswordSalt,
              let verifier = user.decoyPasswordVerifier,
              let candidate = try? Self.decoyVerifier(password: password, salt: salt, rounds: rounds) else {
            return false
        }
        return candidate == verifier
    }

    private func destroyLocalVaultAfterDecoyPassword() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                try FileManager.default.removeItem(at: vaultURL)
            }
            let attachmentsRoot = attachmentsRootURL()
            if FileManager.default.fileExists(atPath: attachmentsRoot.path) {
                try FileManager.default.removeItem(at: attachmentsRoot)
            }
        } catch {
            errorMessage = "无法确认本地数据已销毁，请检查文件权限并手动删除保险库文件：\(error.localizedDescription)"
            state = .locked
            return false
        }
        vaultFile = nil
        vaultKey = nil
        currentUserID = nil
        notes.removeAll(keepingCapacity: false)
        vaultItems.removeAll(keepingCapacity: false)
        securityLogs.removeAll(keepingCapacity: false)
        imagePreviewCache.removeAll(keepingCapacity: false)
        signedInUsername = nil
        userCount = 0
        accounts = []
        recoveryCodeToShow = nil
        isDecoySession = false
        autoLockMinutes = 5
        state = .needsAdminSetup
        errorMessage = nil
        return true
    }

    nonisolated private static func decoyVerifier(password: String, salt: Data, rounds: UInt32) throws -> Data {
        let key = try CryptoService.deriveKey(password: password, salt: salt, rounds: rounds)
        var input = key.withUnsafeBytes { Data($0) }
        input.append(decoyVerifierContext)
        return Data(SHA256.hash(data: input))
    }

    private func decoyKey(password: String, for user: UserRecord, rounds: UInt32) throws -> Data? {
        guard let salt = user.decoyPasswordSalt else { return nil }
        let key = try CryptoService.deriveKey(password: password, salt: salt, rounds: rounds)
        return key.withUnsafeBytes { Data($0) }
    }

    private func decodeNotes(from encryptedNotes: Data, rawKey: Data) throws -> [Note] {
        try decodePayload(from: encryptedNotes, rawKey: rawKey).notes
    }

    private func decodePayload(from encryptedNotes: Data, rawKey: Data) throws -> VaultPayload {
        let cleartext = try CryptoService.open(encryptedNotes, using: SymmetricKey(data: rawKey))
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(VaultPayload.self, from: cleartext) {
            return VaultPayload(notes: payload.notes.map { note in
                var clean = note
                clean.attachments = []
                return clean
            }, vaultItems: payload.vaultItems, securityLogs: payload.securityLogs)
        }
        do {
            let decodedNotes = try decoder.decode([Note].self, from: cleartext)
            let migratedItems = decodedNotes.flatMap(\.attachments)
            let cleanNotes = decodedNotes.map { note in
                var clean = note
                clean.attachments = []
                return clean
            }
            return VaultPayload(notes: cleanNotes, vaultItems: migratedItems, securityLogs: [])
        } catch {
            throw VaultError.corruptVault
        }
    }

    private func validateUsernameFormat(_ username: String) throws -> String {
        CryptoService.normalizedUsername(username)
    }

    nonisolated private static func displayName(for username: String) -> String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名账户" : trimmed
    }

    private func findUser(username: String, in file: VaultFile) throws -> UserRecord? {
        guard let index = try findUserIndex(username: username, in: file) else { return nil }
        return file.users[index]
    }

    private func findUserIndex(username: String, in file: VaultFile) throws -> Int? {
        let normalized = try validateUsernameFormat(username)
        return file.users.firstIndex { user in
            guard let salt = user.usernameSalt, let expected = user.usernameHash else { return false }
            return CryptoService.usernameHash(normalized, salt: salt) == expected
        }
    }

    private func makeRecoveryWrap(for rawKey: Data) throws -> (code: String, salt: Data, wrappedVaultKey: Data) {
        let code = try Self.generateRecoveryCode()
        let salt = try CryptoService.randomData(count: 16)
        let key = try recoveryKey(for: code, salt: salt)
        let wrappedVaultKey = try CryptoService.seal(rawKey, using: key)
        return (code, salt, wrappedVaultKey)
    }

    private func recoveryKey(for code: String, salt: Data) throws -> SymmetricKey {
        try CryptoService.deriveKey(password: Self.normalizedRecoveryCode(code), salt: salt, rounds: CryptoService.defaultRounds)
    }

    nonisolated private static func generateRecoveryCode() throws -> String {
        let bytes = try CryptoService.randomData(count: 16)
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4)
            .map { start -> String in
                let lower = hex.index(hex.startIndex, offsetBy: start)
                let upper = hex.index(lower, offsetBy: 4)
                return String(hex[lower..<upper])
            }
            .joined(separator: "-")
    }

    nonisolated private static func normalizedRecoveryCode(_ code: String) -> String {
        let allowed = Set("0123456789ABCDEF")
        return String(code.uppercased().filter { allowed.contains($0) })
    }

    private func validateCurrentUserPassword(_ password: String, against file: VaultFile) throws {
        guard let currentUserID,
              let user = file.users.first(where: { $0.id == currentUserID }) else {
            throw VaultError.invalidUsername
        }
        let passwordKey = try CryptoService.deriveKey(password: password, salt: user.passwordSalt, rounds: passwordRounds(for: user, in: file))
        _ = try CryptoService.open(user.wrappedVaultKey, using: passwordKey)
    }

    private func passwordRounds(for user: UserRecord, in file: VaultFile) -> UInt32 {
        guard let configuration = user.passwordKDF,
              configuration.algorithm == "PBKDF2-HMAC-SHA256",
              configuration.rounds >= 100_000 else { return file.rounds }
        return configuration.rounds
    }

    private static func adminVerifier(for key: SymmetricKey) -> Data {
        var input = key.withUnsafeBytes { Data($0) }
        input.append(Data("ciphernotes-admin-v1".utf8))
        return Data(SHA256.hash(data: input))
    }

    private func persist() {
        guard var file = vaultFile, let vaultKey, let currentUserID else { return }
        do {
            guard let index = file.users.firstIndex(where: { $0.id == currentUserID }) else { throw VaultError.corruptVault }
            let payload = VaultPayload(notes: notes.map { note in
                var clean = note
                clean.attachments = []
                return clean
            }, vaultItems: vaultItems, securityLogs: securityLogs)
            let encryptedPayload = try CryptoService.seal(try JSONEncoder().encode(payload), using: SymmetricKey(data: vaultKey))
            if isDecoySession {
                file.users[index].decoyEncryptedNotes = encryptedPayload
            } else {
                file.users[index].encryptedNotes = encryptedPayload
            }
            file.users[index].updatedAt = .now
            file.updatedAt = .now
            try write(file)
            vaultFile = file
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func readVaultFile() throws -> VaultFile {
        do {
            let file = try JSONDecoder().decode(VaultFile.self, from: Data(contentsOf: vaultURL))
            guard file.version == Self.vaultVersion else { throw VaultError.corruptVault }
            return file
        } catch {
            let recoveryURL = vaultRecoveryURL()
            guard let data = try? Data(contentsOf: recoveryURL),
                  let recovered = try? JSONDecoder().decode(VaultFile.self, from: data),
                  recovered.version == Self.vaultVersion else { throw VaultError.corruptVault }
            try? data.write(to: vaultURL, options: [.atomic])
            return recovered
        }
    }

    private func readLegacyFile() throws -> LegacyVaultFile {
        do {
            let file = try JSONDecoder().decode(LegacyVaultFile.self, from: Data(contentsOf: vaultURL))
            guard file.version == 1 else { throw VaultError.corruptVault }
            return file
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.corruptVault
        }
    }

    private func write(_ file: VaultFile) throws {
        try FileManager.default.createDirectory(at: vaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(file)
        if FileManager.default.fileExists(atPath: vaultURL.path),
           let existing = try? Data(contentsOf: vaultURL),
           (try? JSONDecoder().decode(VaultFile.self, from: existing)) != nil {
            try existing.write(to: vaultRecoveryURL(), options: [.atomic])
        }
        try data.write(to: vaultURL, options: [.atomic])
    }

    private func vaultRecoveryURL() -> URL {
        vaultURL.deletingPathExtension().appendingPathExtension("previous.json")
    }

    private func refreshAccounts(from file: VaultFile) {
        accounts = Self.accountSummaries(from: file)
        userCount = file.users.count
    }

    private func touchActivity() { lastActivity = .now }

    private func canAttemptAuthentication(_ identifier: String) -> Bool {
        guard let blockedUntil = authenticationBlockedUntil[identifier] else { return true }
        let remaining = blockedUntil.timeIntervalSinceNow
        guard remaining > 0 else {
            authenticationBlockedUntil[identifier] = nil
            return true
        }
        errorMessage = "登录失败次数过多，请在 \(Int(ceil(remaining))) 秒后重试"
        return false
    }

    private func registerAuthenticationFailure(for identifier: String) {
        let count = (authenticationFailureCounts[identifier] ?? 0) + 1
        authenticationFailureCounts[identifier] = count
        guard count >= 3 else { return }
        let delay = min(30.0, pow(2.0, Double(min(count - 3, 5))))
        authenticationBlockedUntil[identifier] = Date().addingTimeInterval(delay)
    }

    private func clearAuthenticationFailures(for identifier: String) {
        authenticationFailureCounts[identifier] = nil
        authenticationBlockedUntil[identifier] = nil
    }

    private func installPrivacyObservers() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            Task { @MainActor in self?.touchActivity() }
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .unlocked else { return }
                if Date().timeIntervalSince(self.lastActivity) >= Double(self.autoLockMinutes * 60) { self.lock() }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
        notificationTokens.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        })
    }

    nonisolated private static func defaultVaultURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["CIPHERNOTES_VAULT_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CipherNotes", isDirectory: true).appendingPathComponent("vault.json")
    }

    nonisolated private static func initialState(for url: URL) -> VaultState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .needsAdminSetup }
        guard let data = try? Data(contentsOf: url) else { return .locked }
        if let file = try? JSONDecoder().decode(VaultFile.self, from: data), file.version == vaultVersion {
            return file.users.isEmpty ? .needsAdminSetup : .locked
        }
        if let legacy = try? JSONDecoder().decode(LegacyVaultFile.self, from: data), legacy.version == 1 {
            return .needsMigration
        }
        return .locked
    }

    nonisolated private static func userCount(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(VaultFile.self, from: data),
              file.version == vaultVersion else {
            return 0
        }
        return file.users.count
    }

    nonisolated private static func accountSummaries(at url: URL) -> [AccountSummary] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(VaultFile.self, from: data),
              file.version == vaultVersion else {
            return []
        }
        return accountSummaries(from: file)
    }

    nonisolated private static func accountSummaries(from file: VaultFile) -> [AccountSummary] {
        file.users.enumerated().map { index, user in
            AccountSummary(
                id: user.id,
                displayName: user.displayName?.isEmpty == false ? user.displayName! : "旧账户 \(index + 1)",
                touchIDEnabled: user.touchIDEnabled,
                advancedDataProtectionEnabled: user.advancedDataProtectionEnabled,
                decoyPasswordEnabled: user.decoyPasswordSalt != nil && user.decoyPasswordVerifier != nil,
                role: user.role
            )
        }
    }

    private func cleanOrphanedAttachments() {
        let rootURL = attachmentsRootURL()
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let knownUserIDs = Set(accounts.map(\.id) + userIDsInVaultFile())
        var removed = 0
        for entry in entries {
            guard let isDirectory = try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory else { continue }
            let dirName = entry.lastPathComponent
            guard let dirID = UUID(uuidString: dirName), !knownUserIDs.contains(dirID) else { continue }
            try? FileManager.default.removeItem(at: entry)
            removed += 1
        }
        if removed > 0 { errorMessage = "启动时清理了 \(removed) 个已注销用户的残留加密文件" }
    }

    nonisolated private func userIDsInVaultFile() -> Set<UUID> {
        guard let data = try? Data(contentsOf: vaultURL),
              let file = try? JSONDecoder().decode(VaultFile.self, from: data) else { return [] }
        return Set(file.users.map(\.id))
    }

    func backupVault(to destinationURL: URL) {
        guard !vaultImportJobs.contains(where: \.isActive) else {
            errorMessage = "请等待保险柜文件导入完成后再备份"
            return
        }
        let accessing = destinationURL.startAccessingSecurityScopedResource()
        defer { if accessing { destinationURL.stopAccessingSecurityScopedResource() } }
        let dateTag = Self.backupDateFormatter.string(from: .now)
        let backupDir = destinationURL.appendingPathComponent("密笺备份 \(dateTag)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                try FileManager.default.copyItem(at: vaultURL, to: backupDir.appendingPathComponent("vault.json"))
            }
            let attachmentsRoot = attachmentsRootURL()
            if FileManager.default.fileExists(atPath: attachmentsRoot.path) {
                try FileManager.default.copyItem(at: attachmentsRoot, to: backupDir.appendingPathComponent("Attachments", isDirectory: true))
            }
            let hashes = try Self.backupFileHashes(in: backupDir)
            let manifest = BackupManifest(
                formatVersion: 1,
                vaultVersion: Self.vaultVersion,
                createdAt: .now,
                fileHashes: hashes
            )
            try JSONEncoder().encode(manifest).write(
                to: backupDir.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        } catch {
            errorMessage = "备份失败：\(error.localizedDescription)"
            recordSecurityEvent(.backupCreated, result: .failure, message: "保险库备份失败")
            return
        }
        errorMessage = "保险库已备份到选定文件夹"
        recordSecurityEvent(.backupCreated, message: "保险库已备份")
    }

    func restoreVault(from backupURL: URL, currentPassword: String, confirmationText: String) {
        guard state == .unlocked else {
            errorMessage = "请先解锁当前账户再还原保险库"
            return
        }
        guard confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "还原保险库" else {
            errorMessage = "请输入“还原保险库”以确认"
            return
        }
        let accessing = backupURL.startAccessingSecurityScopedResource()
        defer { if accessing { backupURL.stopAccessingSecurityScopedResource() } }
        let backupVaultURL = backupURL.appendingPathComponent("vault.json")
        guard FileManager.default.fileExists(atPath: backupVaultURL.path) else {
            errorMessage = "备份文件夹不包含 vault.json"
            return
        }
        guard let data = try? Data(contentsOf: backupVaultURL),
              let decodedBackup = try? JSONDecoder().decode(VaultFile.self, from: data),
              decodedBackup.version == Self.vaultVersion else {
            errorMessage = "备份文件无效或已损坏"
            return
        }
        let manifestURL = backupURL.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            guard let manifestData = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(BackupManifest.self, from: manifestData),
                  manifest.formatVersion == 1,
                  manifest.vaultVersion == Self.vaultVersion,
                  (try? Self.validateBackupHashes(manifest.fileHashes, in: backupURL)) == true else {
                errorMessage = "备份完整性校验失败，未更改当前保险库"
                recordSecurityEvent(.backupRestored, result: .failure, message: "备份完整性校验失败")
                return
            }
        }
        do {
            try validateCurrentUserPassword(currentPassword, against: try readVaultFile())
            recordSecurityEvent(.backupRestored, message: "保险库即将从备份还原")
        } catch {
            errorMessage = (error as? VaultError)?.localizedDescription ?? "当前账户密码不正确"
            return
        }
        if state == .unlocked { lock() }
        do {
            if FileManager.default.fileExists(atPath: vaultURL.path) {
                try FileManager.default.removeItem(at: vaultURL)
            }
            try FileManager.default.copyItem(at: backupVaultURL, to: vaultURL)
            let attachmentsRoot = attachmentsRootURL()
            if FileManager.default.fileExists(atPath: attachmentsRoot.path) {
                try FileManager.default.removeItem(at: attachmentsRoot)
            }
            let backupAttachments = backupURL.appendingPathComponent("Attachments", isDirectory: true)
            if FileManager.default.fileExists(atPath: backupAttachments.path) {
                try FileManager.default.copyItem(at: backupAttachments, to: attachmentsRoot)
            }
        } catch {
            errorMessage = "还原失败，当前保险库可能已损坏：\(error.localizedDescription)"
            state = Self.initialState(for: vaultURL)
            userCount = Self.userCount(at: vaultURL)
            accounts = Self.accountSummaries(at: vaultURL)
            return
        }
        state = Self.initialState(for: vaultURL)
        userCount = Self.userCount(at: vaultURL)
        accounts = Self.accountSummaries(at: vaultURL)
        imagePreviewCache.removeAll(keepingCapacity: false)
        cleanOrphanedAttachments()
        errorMessage = "保险库已从备份还原，请重新登录"
    }

    nonisolated private static var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }

    nonisolated private static func backupFileHashes(in directory: URL) throws -> [String: String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            throw VaultError.corruptVault
        }
        var hashes: [String: String] = [:]
        for case let fileURL as URL in enumerator {
            guard (try fileURL.resourceValues(forKeys: Set(keys))).isRegularFile == true,
                  fileURL.lastPathComponent != "manifest.json" else { continue }
            let basePath = directory.standardizedFileURL.path
            let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(prefix) else { throw VaultError.corruptVault }
            let relative = String(filePath.dropFirst(prefix.count))
            hashes[relative] = try sha256Hex(of: fileURL)
        }
        return hashes
    }

    nonisolated private static func validateBackupHashes(_ expected: [String: String], in directory: URL) throws -> Bool {
        guard !expected.isEmpty else { return false }
        for (relative, hash) in expected {
            let fileURL = directory.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  try sha256Hex(of: fileURL) == hash else { return false }
        }
        return true
    }

    nonisolated private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
