import Foundation

/// Cancel flag for one running action. Tools started on a thread while the token is active
/// (`activate`) belong to it; `cancel()` stops those tools only — never other work's.
public final class CancelToken: @unchecked Sendable {
    private static let threadKey = "dev.peel.cancelToken"
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [ObjectIdentifier: Process] = [:]

    public init() {}

    /// The token active on the current thread, if any.
    static var current: CancelToken? { Thread.current.threadDictionary[threadKey] as? CancelToken }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Runs `body` with this token active on the current thread.
    public func activate<T>(_ body: () throws -> T) rethrows -> T {
        let previous = Thread.current.threadDictionary[Self.threadKey]
        Thread.current.threadDictionary[Self.threadKey] = self
        defer { Thread.current.threadDictionary[Self.threadKey] = previous }
        return try body()
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let running = Array(processes.values)
        lock.unlock()
        running.filter(\.isRunning).forEach { $0.terminate() }
    }

    /// Registers a tool that is about to start; if already cancelled, it is stopped as soon as it runs.
    func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    func unregister(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = nil
        lock.unlock()
    }
}
