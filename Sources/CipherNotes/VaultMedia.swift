import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

struct VaultMediaResource: Identifiable, @unchecked Sendable {
    let id: UUID
    let fileName: String
    let contentType: String?
    let byteCount: Int
    let reader: EncryptedAttachmentReader
}

final class SendableNSImage: @unchecked Sendable {
    let image: NSImage

    init(_ image: NSImage) {
        self.image = image
    }
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
    private var legacyCleartextCache: Data?
    private let cacheLock = NSLock()
    private let inputLock = NSLock()
    private var persistentInput: FileHandle?
    private var decryptedChunkCache: [Int: Data] = [:]
    private var decryptedChunkOrder: [Int] = []
    private var decryptionOperations = 0
    private let maximumCachedChunks = 3

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
            cacheLock.lock()
            if let cached = legacyCleartextCache {
                cacheLock.unlock()
                return cached.subdata(in: lower..<upper)
            }
            cacheLock.unlock()
            let cleartext = try CryptoService.open(legacyCiphertext, using: .init(data: rawKey))
            cacheLock.lock()
            legacyCleartextCache = cleartext
            decryptionOperations += 1
            cacheLock.unlock()
            return cleartext.subdata(in: lower..<upper)
        }

        inputLock.lock()
        defer { inputLock.unlock() }
        let input: FileHandle
        if let persistentInput {
            input = persistentInput
        } else {
            input = try FileHandle(forReadingFrom: url)
            persistentInput = input
        }
        var output = Data()
        output.reserveCapacity(upper - lower)
        for (index, chunk) in chunks.enumerated()
        where chunk.plaintextOffset < upper && chunk.plaintextOffset + chunk.plaintextLength > lower {
            let cleartext = try decryptedChunk(at: index, chunk: chunk, input: input)
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

    var decryptionOperationCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return decryptionOperations
    }

    func makeRandomAccessDataProvider() -> CGDataProvider? {
        guard byteCount > 0 else { return nil }
        let context = Unmanaged.passRetained(EncryptedImageProviderContext(reader: self))
        var callbacks = CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: nil,
            releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, position, count in
                guard let info else { return 0 }
                let context = Unmanaged<EncryptedImageProviderContext>.fromOpaque(info).takeUnretainedValue()
                guard position >= 0, count > 0 else { return 0 }
                let start = Int(position)
                guard start < context.reader.byteCount else { return 0 }
                let end = start + min(count, context.reader.byteCount - start)
                guard start < end, let data = try? context.reader.read(range: start..<end) else { return 0 }
                data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
                return data.count
            },
            releaseInfo: { info in
                guard let info else { return }
                Unmanaged<EncryptedImageProviderContext>.fromOpaque(info).release()
            }
        )
        guard let provider = CGDataProvider(
            directInfo: context.toOpaque(),
            size: off_t(byteCount),
            callbacks: &callbacks
        ) else {
            context.release()
            return nil
        }
        return provider
    }

    private func decryptedChunk(at index: Int, chunk: Chunk, input: FileHandle) throws -> Data {
        cacheLock.lock()
        if let cached = decryptedChunkCache[index] {
            decryptedChunkOrder.removeAll { $0 == index }
            decryptedChunkOrder.append(index)
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        try input.seek(toOffset: chunk.encryptedOffset)
        let encrypted = try Self.readExact(from: input, count: chunk.encryptedLength)
        let cleartext = try CryptoService.open(encrypted, using: .init(data: rawKey))
        guard cleartext.count == chunk.plaintextLength else { throw VaultError.corruptVault }

        cacheLock.lock()
        decryptionOperations += 1
        decryptedChunkCache[index] = cleartext
        decryptedChunkOrder.removeAll { $0 == index }
        decryptedChunkOrder.append(index)
        while decryptedChunkOrder.count > maximumCachedChunks {
            decryptedChunkCache[decryptedChunkOrder.removeFirst()] = nil
        }
        cacheLock.unlock()
        return cleartext
    }

    private static func readExact(from handle: FileHandle, count: Int) throws -> Data {
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw VaultError.corruptVault }
        return data
    }

    deinit {
        try? persistentInput?.close()
    }
}

private final class EncryptedImageProviderContext: @unchecked Sendable {
    let reader: EncryptedAttachmentReader

    init(reader: EncryptedAttachmentReader) {
        self.reader = reader
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
    private var cleanedUp = false

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
        let target = CMTime(seconds: min(max(seconds, 0), max(duration, 0)), preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.08, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func stopAndClear() {
        guard !cleanedUp else { return }
        cleanedUp = true
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.replaceCurrentItem(with: nil)
        isPlaying = false
    }
}
