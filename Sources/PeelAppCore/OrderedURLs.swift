import Foundation

/// Collects file URLs that load asynchronously (one per dragged item) and returns them in drag order,
/// whatever order they finish in. Thread-safe.
public final class OrderedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]

    public init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    public func set(_ index: Int, _ url: URL?) {
        lock.lock()
        if slots.indices.contains(index) { slots[index] = url }
        lock.unlock()
    }

    public var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}
