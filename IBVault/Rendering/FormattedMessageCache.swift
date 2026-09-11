import Foundation

/// Lightweight in-memory cache for finalized message parses so scroll/resize
/// and unrelated state changes never re-parse. Keyed by content hash, bounded
/// to avoid unbounded growth. Thread-safe via NSLock.
final class FormattedMessageCache: @unchecked Sendable {
    nonisolated static let shared = FormattedMessageCache()

    private let lock = NSLock()
    nonisolated(unsafe) private var store: [Int: [FormattedMessageSection]] = [:]
    nonisolated(unsafe) private var order: [Int] = []
    private let maxEntries = 256

    nonisolated func cachedSections(for text: String) -> [FormattedMessageSection]? {
        let key = text.hashValue
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    nonisolated func store(sections: [FormattedMessageSection], for text: String) {
        let key = text.hashValue
        lock.lock()
        defer { lock.unlock() }
        if store[key] == nil {
            order.append(key)
            if order.count > maxEntries, let oldest = order.first {
                order.removeFirst()
                store.removeValue(forKey: oldest)
            }
        }
        store[key] = sections
    }
}
