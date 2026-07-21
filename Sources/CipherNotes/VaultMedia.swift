import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct VaultMediaResource: Identifiable, @unchecked Sendable {
    let id: UUID
    let fileName: String
    let contentType: String?
    let byteCount: Int
    let reader: EncryptedAttachmentReader
}

final class EncryptedAttachmentReader: @unchecked Sendable {
    private struct Chunk: Sendable {
        let encryptedOffset: UInt64
        let encryptedLength: Int
        let plaintextOffset: Int
        let plaintextLength: Int
    }

    let byteCount: Int
    private let url: URL
    private let rawKey: Data
    private let chunks: [Chunk]
    private let legacyCiphertext: Data?

    init(url: URL, rawKey: Data, magic: Data, maximumEncryptedChunkSize: Int, encryptedChunkOverhead: Int) throws {
        self.url = url
        self.rawKey = rawKey

        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let prefix = try input.read(upToCount: magic.count) ?? Data()
        guard prefix == magic else {
            let encrypted = try Data(contentsOf: url, options: .mappedIfSafe)
            let cleartext = try CryptoService.open(encrypted, using: .init(data: rawKey))
            byteCount = cleartext.count
            chunks = []
            legacyCiphertext = encrypted
            return
        }

        let countData = try Self.readExact(from: input, count: 8)
        let declaredCount = countData.enumerated().reduce(UInt64(0)) { result, pair in
            result | (UInt64(pair.element) << UInt64(pair.offset * 8))
        }
        guard declaredCount <= UInt64(Int.max) else { throw VaultError.corruptVault }

        var scannedChunks: [Chunk] = []
        var plaintextOffset = 0
        while true {
            let lengthData = try input.read(upToCount: 4) ?? Data()
            if lengthData.isEmpty { break }
            guard lengthData.count == 4 else { throw VaultError.corruptVault }
            let encryptedLength = Int(lengthData.enumerated().reduce(UInt32(0)) { result, pair in
                result | (UInt32(pair.element) << UInt32(pair.offset * 8))
            })
            guard encryptedLength > encryptedChunkOverhead,
                  encryptedLength <= maximumEncryptedChunkSize else { throw VaultError.corruptVault }
            let encryptedOffset = try input.offset()
            let plaintextLength = encryptedLength - encryptedChunkOverhead
            scannedChunks.append(Chunk(
                encryptedOffset: encryptedOffset,
                encryptedLength: encryptedLength,
                plaintextOffset: plaintextOffset,
                plaintextLength: plaintextLength
            ))
            plaintextOffset += plaintextLength
            try input.seek(toOffset: encryptedOffset + UInt64(encryptedLength))
        }
        guard plaintextOffset == Int(declaredCount) else { throw VaultError.corruptVault }
        byteCount = plaintextOffset
        chunks = scannedChunks
        legacyCiphertext = nil
    }

    func read(range requestedRange: Range<Int>) throws -> Data {
        let lower = max(0, min(requestedRange.lowerBound, byteCount))
        let upper = max(lower, min(requestedRange.upperBound, byteCount))
        guard lower < upper else { return Data() }

        if let legacyCiphertext {
            let cleartext = try CryptoService.open(legacyCiphertext, using: .init(data: rawKey))
            return cleartext.subdata(in: lower..<upper)
        }

        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var output = Data()
        output.reserveCapacity(upper - lower)
        for chunk in chunks where chunk.plaintextOffset < upper && chunk.plaintextOffset + chunk.plaintextLength > lower {
            try input.seek(toOffset: chunk.encryptedOffset)
            let encrypted = try Self.readExact(from: input, count: chunk.encryptedLength)
            let cleartext = try CryptoService.open(encrypted, using: .init(data: rawKey))
            guard cleartext.count == chunk.plaintextLength else { throw VaultError.corruptVault }
            let localLower = max(0, lower - chunk.plaintextOffset)
            let localUpper = min(cleartext.count, upper - chunk.plaintextOffset)
            output.append(cleartext.subdata(in: localLower..<localUpper))
        }
        guard output.count == upper - lower else { throw VaultError.corruptVault }
        return output
    }

    func readAll(maximumBytes: Int? = nil) throws -> Data {
        if let maximumBytes, byteCount > maximumBytes { throw VaultError.fileTooLarge }
        return try read(range: 0..<byteCount)
    }

    private static func readExact(from handle: FileHandle, count: Int) throws -> Data {
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw VaultError.corruptVault }
        return data
    }
}

final class VaultMediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let resource: VaultMediaResource

    init(resource: VaultMediaResource) {
        self.resource = resource
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        do {
            if let information = loadingRequest.contentInformationRequest {
                information.contentLength = Int64(resource.byteCount)
                information.isByteRangeAccessSupported = true
                information.contentType = resolvedTypeIdentifier
            }
            if let request = loadingRequest.dataRequest {
                let start = Int(max(request.currentOffset, request.requestedOffset))
                let end = min(resource.byteCount, start + request.requestedLength)
                request.respond(with: try resource.reader.read(range: start..<end))
            }
            loadingRequest.finishLoading()
        } catch {
            loadingRequest.finishLoading(with: error)
        }
        return true
    }

    private var resolvedTypeIdentifier: String {
        if let contentType = resource.contentType,
           let type = UTType(mimeType: contentType) {
            return type.identifier
        }
        let extensionName = URL(fileURLWithPath: resource.fileName).pathExtension
        return UTType(filenameExtension: extensionName)?.identifier ?? UTType.data.identifier
    }
}

@MainActor
final class VaultMediaPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isReady = false
    @Published private(set) var errorText: String?

    let player: AVPlayer
    private let loader: VaultMediaResourceLoader
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init(resource: VaultMediaResource) {
        loader = VaultMediaResourceLoader(resource: resource)
        let url = URL(string: "ciphernote-media://local/\(resource.id.uuidString)/\(resource.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "media")")!
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "app.ciphernotes.media-loader", qos: .userInitiated))
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? max(0, seconds) : 0
                case .failed:
                    self.errorText = "无法读取这个媒体文件"
                default:
                    break
                }
            }
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                self.isPlaying = self.player.timeControlStatus == .playing
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.player.seek(to: .zero)
            }
        }
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: min(max(seconds, 0), max(duration, 0)), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stopAndClear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
    }

}
