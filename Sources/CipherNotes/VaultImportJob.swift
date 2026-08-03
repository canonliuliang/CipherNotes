import Foundation

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

final class VaultImportCancellationToken: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var paused = false

    func cancel() {
        condition.lock()
        guard !cancelled else { condition.unlock(); return }
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
        guard !cancelled else { condition.unlock(); return }
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

