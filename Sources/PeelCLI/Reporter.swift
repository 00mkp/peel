import ArgumentParser
import ConvertKit
import Foundation

/// Prints ✓/✗ lines, a summary for batches, and turns any failure into exit code 1.
final class Reporter {
    let verbose: Bool
    private(set) var succeeded = 0
    private(set) var failed = 0

    init(verbose: Bool = false) {
        self.verbose = verbose
    }

    func record(_ input: URL?, outputs: [URL]) {
        succeeded += 1
        for url in outputs { Console.out("✓ \(Paths.display(url))") }
    }

    func failure(_ input: URL?, _ error: Error) {
        failed += 1
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        Console.err(input.map { "✗ \($0.lastPathComponent): \(message)" } ?? "✗ \(message)")
        if verbose, let peelError = error as? PeelError,
           case let .toolFailed(_, _, _, details) = peelError, !details.isEmpty {
            Console.err(details)
        }
    }

    func finish(verb: String = "processed") throws {
        let total = succeeded + failed
        if total > 1 {
            Console.out("\(verb) \(succeeded)/\(total) files" + (failed > 0 ? " (\(failed) failed)" : ""))
        }
        if failed > 0 { throw ExitCode(1) }
    }
}

/// One input → one output with standard naming, reporting and exit code.
/// `ext` defaults to the input's own extension.
func runSingle(_ file: String, suffix: String, ext: String? = nil, options: OutputOptions,
               _ operation: (_ input: URL, _ output: URL) throws -> Void) throws {
    let input = Paths.url(file)
    let reporter = Reporter(verbose: options.verbose)
    do {
        try Paths.requireExists(input)
        let outputExt = ext ?? OutputPlanner.splitName(input.lastPathComponent).ext
        let output = options.planner.plan(input: input, suffix: suffix, ext: outputExt, output: options.outputURL)
        try operation(input, output)
        reporter.record(input, outputs: [output])
    } catch {
        reporter.failure(input, error)
    }
    try reporter.finish()
}
