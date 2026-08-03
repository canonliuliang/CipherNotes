import AppKit
import Foundation

final class VaultImageCache: @unchecked Sendable {
    private let cache = NSCache<NSUUID, NSImage>()
    private let lock = NSLock()
    private var keys = Set<UUID>()

    init(totalCostLimit: Int, countLimit: Int) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
        cache.evictsObjectsWithDiscardedContent = true
    }

    func object(forKey key: UUID) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSUUID)
    }

    func setObject(_ obj: NSImage, forKey key: UUID, cost: Int) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(obj, forKey: key as NSUUID, cost: cost)
        keys.insert(key)
    }

    func removeObject(forKey key: UUID) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeObject(forKey: key as NSUUID)
        keys.remove(key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        keys.removeAll()
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return keys.isEmpty
    }

    subscript(key: UUID) -> NSImage? {
        get { object(forKey: key) }
        set {
            if let image = newValue {
                setObject(image, forKey: key, cost: 0)
            } else {
                removeObject(forKey: key)
            }
        }
    }
}

