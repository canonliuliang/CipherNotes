import Foundation

struct VaultAttachment: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var fileName: String
    var contentType: String?
    var byteCount: Int
    var createdAt: Date

    init(id: UUID = UUID(), fileName: String, contentType: String? = nil, byteCount: Int, createdAt: Date = .now) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}

struct Note: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var attachments: [VaultAttachment]
    var tags: [String]
    var isPinned: Bool
    var isFavorite: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "新笔记",
        body: String = "",
        attachments: [VaultAttachment] = [],
        tags: [String] = [],
        isPinned: Bool = false,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.attachments = attachments
        self.tags = tags
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case attachments
        case tags
        case isPinned
        case isFavorite
        case isArchived
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        attachments = try container.decodeIfPresent([VaultAttachment].self, forKey: .attachments) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct VaultPayload: Codable, Equatable, Sendable {
    var notes: [Note]
    var vaultItems: [VaultAttachment]
}

struct VaultFile: Codable, Sendable {
    let version: Int
    let rounds: UInt32
    let adminSalt: Data
    let adminVerifier: Data
    var users: [UserRecord]
    var updatedAt: Date
}

struct AccountSummary: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    var touchIDEnabled: Bool = false
    var advancedDataProtectionEnabled: Bool = false
    var role: AccountRole = .standard
}

enum AccountRole: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case admin
    case standard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .admin: "管理员账号"
        case .standard: "普通账号"
        }
    }

    var shortLabel: String {
        switch self {
        case .admin: "管理员"
        case .standard: "普通"
        }
    }
}

struct UpdateLogEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let version: String
    let title: String
    let dateText: String
    let items: [String]
}

struct SharedNotePackage: Codable, Equatable, Sendable {
    let version: Int
    let salt: Data
    let rounds: UInt32
    let encryptedPayload: Data
    let createdAt: Date
}

struct SharedAttachmentPayload: Codable, Equatable, Sendable {
    let fileName: String
    let contentType: String?
    let byteCount: Int
    let data: Data
}

struct SharedNotePayload: Codable, Equatable, Sendable {
    let title: String
    let body: String
    let senderUsername: String?
    let originalCreatedAt: Date
    let sharedAt: Date
    let attachments: [SharedAttachmentPayload]

    init(title: String, body: String, senderUsername: String?, originalCreatedAt: Date, sharedAt: Date, attachments: [SharedAttachmentPayload] = []) {
        self.title = title
        self.body = body
        self.senderUsername = senderUsername
        self.originalCreatedAt = originalCreatedAt
        self.sharedAt = sharedAt
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case senderUsername
        case originalCreatedAt
        case sharedAt
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        senderUsername = try container.decodeIfPresent(String.self, forKey: .senderUsername)
        originalCreatedAt = try container.decode(Date.self, forKey: .originalCreatedAt)
        sharedAt = try container.decode(Date.self, forKey: .sharedAt)
        attachments = try container.decodeIfPresent([SharedAttachmentPayload].self, forKey: .attachments) ?? []
    }
}

struct UserRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String? = nil
    var touchIDEnabled: Bool = false
    var advancedDataProtectionEnabled: Bool = false
    var role: AccountRole = .standard
    var usernameSalt: Data? = nil
    var usernameHash: Data? = nil
    var passwordSalt: Data
    var wrappedVaultKey: Data
    var recoverySalt: Data? = nil
    var recoveryWrappedVaultKey: Data? = nil
    var encryptedNotes: Data
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case touchIDEnabled
        case advancedDataProtectionEnabled
        case role
        case usernameSalt
        case usernameHash
        case passwordSalt
        case wrappedVaultKey
        case recoverySalt
        case recoveryWrappedVaultKey
        case encryptedNotes
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        displayName: String? = nil,
        touchIDEnabled: Bool = false,
        advancedDataProtectionEnabled: Bool = false,
        role: AccountRole = .standard,
        usernameSalt: Data? = nil,
        usernameHash: Data? = nil,
        passwordSalt: Data,
        wrappedVaultKey: Data,
        recoverySalt: Data? = nil,
        recoveryWrappedVaultKey: Data? = nil,
        encryptedNotes: Data,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.touchIDEnabled = touchIDEnabled
        self.advancedDataProtectionEnabled = advancedDataProtectionEnabled
        self.role = role
        self.usernameSalt = usernameSalt
        self.usernameHash = usernameHash
        self.passwordSalt = passwordSalt
        self.wrappedVaultKey = wrappedVaultKey
        self.recoverySalt = recoverySalt
        self.recoveryWrappedVaultKey = recoveryWrappedVaultKey
        self.encryptedNotes = encryptedNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        touchIDEnabled = try container.decodeIfPresent(Bool.self, forKey: .touchIDEnabled) ?? false
        advancedDataProtectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .advancedDataProtectionEnabled) ?? false
        role = try container.decodeIfPresent(AccountRole.self, forKey: .role) ?? .standard
        usernameSalt = try container.decodeIfPresent(Data.self, forKey: .usernameSalt)
        usernameHash = try container.decodeIfPresent(Data.self, forKey: .usernameHash)
        passwordSalt = try container.decode(Data.self, forKey: .passwordSalt)
        wrappedVaultKey = try container.decode(Data.self, forKey: .wrappedVaultKey)
        recoverySalt = try container.decodeIfPresent(Data.self, forKey: .recoverySalt)
        recoveryWrappedVaultKey = try container.decodeIfPresent(Data.self, forKey: .recoveryWrappedVaultKey)
        encryptedNotes = try container.decode(Data.self, forKey: .encryptedNotes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct LegacyVaultFile: Codable, Sendable {
    let version: Int
    let salt: Data
    let rounds: UInt32
    let wrappedVaultKey: Data
    var encryptedNotes: Data
    var updatedAt: Date
    var usernameSalt: Data? = nil
    var usernameHash: Data? = nil
}

enum VaultState: Equatable {
    case needsAdminSetup
    case needsMigration
    case locked
    case unlocked
}

enum VaultError: LocalizedError {
    case invalidPassword
    case invalidUsername
    case corruptVault
    case passwordRequired
    case usernameInvalid
    case usernameTaken
    case adminPasswordInvalid
    case recoveryCodeMissing
    case biometricsUnavailable
    case touchIDNotConfigured
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPassword: "密码不正确"
        case .invalidUsername: "用户名不正确"
        case .corruptVault: "保险库损坏或无法读取"
        case .passwordRequired: "需要填写这个字段"
        case .usernameInvalid: "用户名不可用"
        case .usernameTaken: "这个用户名已经注册"
        case .adminPasswordInvalid: "管理员密码不正确"
        case .recoveryCodeMissing: "这个用户还没有恢复码，请先登录后生成恢复码"
        case .biometricsUnavailable: "这台 Mac 暂时无法使用 Touch ID"
        case .touchIDNotConfigured: "这个账户还没有启用 Touch ID"
        case .keychain(let status): "钥匙串操作失败（\(status)）"
        }
    }
}
