import CryptoKit
import Foundation

enum VaultBackupService {
    private struct Manifest: Codable {
        let formatVersion: Int
        let vaultVersion: Int
        let createdAt: Date
        let fileHashes: [String: String]
    }

    static func createBackup(
        vaultURL: URL,
        attachmentsURL: URL,
        destinationRoot: URL,
        vaultVersion: Int,
        now: Date = .now
    ) throws -> URL {
        let dateTag = backupDateFormatter.string(from: now)
        let backupDirectory = destinationRoot.appendingPathComponent("密笺备份 \(dateTag)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: vaultURL.path) {
            try FileManager.default.copyItem(at: vaultURL, to: backupDirectory.appendingPathComponent("vault.json"))
        }
        if FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try FileManager.default.copyItem(
                at: attachmentsURL,
                to: backupDirectory.appendingPathComponent("Attachments", isDirectory: true)
            )
        }
        let manifest = Manifest(
            formatVersion: 1,
            vaultVersion: vaultVersion,
            createdAt: now,
            fileHashes: try fileHashes(in: backupDirectory)
        )
        try JSONEncoder().encode(manifest).write(
            to: backupDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        return backupDirectory
    }

    static func validateBackup(at backupURL: URL, vaultVersion: Int) throws -> Bool {
        let manifestURL = backupURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return true }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.formatVersion == 1, manifest.vaultVersion == vaultVersion else { return false }
        return try validateFileHashes(manifest.fileHashes, in: backupURL)
    }

    private static var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }

    private static func fileHashes(in directory: URL) throws -> [String: String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { throw VaultError.corruptVault }
        var hashes: [String: String] = [:]
        for case let fileURL as URL in enumerator {
            guard (try fileURL.resourceValues(forKeys: Set(keys))).isRegularFile == true,
                  fileURL.lastPathComponent != "manifest.json" else { continue }
            let basePath = directory.standardizedFileURL.path
            let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(prefix) else { throw VaultError.corruptVault }
            hashes[String(filePath.dropFirst(prefix.count))] = try sha256Hex(of: fileURL)
        }
        return hashes
    }

    private static func validateFileHashes(_ expected: [String: String], in directory: URL) throws -> Bool {
        guard !expected.isEmpty else { return false }
        for (relativePath, expectedHash) in expected {
            let fileURL = directory.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  try sha256Hex(of: fileURL) == expectedHash else { return false }
        }
        return true
    }

    private static func sha256Hex(of url: URL) throws -> String {
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
