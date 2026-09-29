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

    private var homebrewNoted = false

    /// `label` names a whole-selection job (e.g. "merge") when there's no single input to blame.
    func failure(_ input: URL?, _ error: Error, label: String? = nil) {
        failed += 1
        let message = (error as? PeelError)?.errorDescription ?? error.localizedDescription
        let subject = input?.lastPathComponent ?? label
        Console.err(subject.map { "✗ \($0): \(message)" } ?? "✗ \(message)")
        if let peelError = error as? PeelError, case let .missingTool(name, _) = peelError {
            if let tool = Tool(rawValue: name) { Console.err("  \(name) adds \(tool.enables)") }
            if !homebrewNoted, ToolLocator.standard.homebrew == nil {
                homebrewNoted = true   // once per run, not once per file
                Console.err("  " + ToolLocator.homebrewMissingNote)
            }
        }
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
