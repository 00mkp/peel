import ConvertKit
import Foundation
@testable import PeelCLI

struct CLIResult {
    let code: Int32
    let out: [String]
    let err: [String]
    var stdout: String { out.joined(separator: "\n") }
    var stderr: String { err.joined(separator: "\n") }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}

/// Runs peel in-process with output captured. Console is task-local, so tests can run in parallel.
func runPeel(_ arguments: [String]) -> CLIResult {
    let out = Lines()
    let err = Lines()
    let code = Console.$current.withValue(Console(out: { out.append($0) }, err: { err.append($0) })) {
        Peel.execute(arguments)
    }
    return CLIResult(code: code, out: out.all, err: err.all)
}

/// The built `peel` executable (scripts/test.sh builds it before the tests run).
let peelBinary = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".build/debug/peel")

/// Runs the real binary — for behaviour that depends on the process environment.
func runBinary(_ arguments: [String], environment: [String: String] = [:]) throws -> (code: Int32, out: String, err: String) {
    let result = try ProcessRunner.run(peelBinary, arguments, environment: environment)
    return (result.exitCode, result.stdout, result.stderr)
}
