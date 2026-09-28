import Foundation

/// On Ctrl-C (SIGINT) or SIGTERM: stop running tools, delete in-flight temp outputs, exit 128+signal.
/// AtomicOutput and ProcessRunner register what they have in flight; the CLI calls `install()` once.
public enum InterruptCleanup {
    private static let lock = NSLock()
    private static var temps: Set<URL> = []
    private static var processes: [ObjectIdentifier: Process] = [:]
    private static var sources: [DispatchSourceSignal] = []

    public static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard sources.isEmpty else { return }
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler { cleanUpAndExit(signalNumber) }
            source.resume()
            sources.append(source)
        }
    }

    static func track(_ url: URL) { lock.lock(); temps.insert(url); lock.unlock() }
    static func untrack(_ url: URL) { lock.lock(); temps.remove(url); lock.unlock() }
    static func track(_ process: Process) { lock.lock(); processes[ObjectIdentifier(process)] = process; lock.unlock() }
    static func untrack(_ process: Process) { lock.lock(); processes[ObjectIdentifier(process)] = nil; lock.unlock() }

    private static func cleanUpAndExit(_ signalNumber: Int32) -> Never {
        lock.lock()
        let running = Array(processes.values)
        let inFlight = temps
        lock.unlock()
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while running.contains(where: \.isRunning) && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        for url in inFlight { try? FileManager.default.removeItem(at: url) }
        exit(128 + signalNumber)
    }
}
