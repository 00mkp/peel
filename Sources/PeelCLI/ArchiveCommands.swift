import ArgumentParser
import ConvertKit
import Foundation

struct ExtractCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "x",
        abstract: "Extract any archive (zip, tar, tar.gz/bz2/xz, gz, rar, 7z) into a folder next to it.")

    @Argument(help: "Archives to extract.") var archives: [String]
    @OptionGroup var options: OutputOptions

    func validate() throws {
        guard !archives.isEmpty else { throw ValidationError("give at least one archive") }
    }

    func run() throws {
        let reporter = Reporter(verbose: options.verbose)
        let inputs = archives.map(Paths.url)
        var produced: [URL] = []
        for archive in inputs {
            do {
                // Never overwrite another archive in the selection or an earlier result.
                let created = try ArchiveBackend.extract(archive, into: options.outputDirectoryURL, planner: options.planner,
                                                         protecting: inputs + produced)
                produced.append(created)
                reporter.record(archive, outputs: [created])
            } catch {
                reporter.failure(archive, error)
            }
        }
        try reporter.finish(verb: "extracted")
    }
}

struct ZipCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zip",
        abstract: "Bundle files and folders into a .zip (or .tar.gz / .tar, chosen by the -o name).")

    @Argument(help: "Files and folders to include.") var paths: [String]
    @OptionGroup var options: OutputOptions

    func validate() throws {
        guard !paths.isEmpty else { throw ValidationError("give at least one file or folder") }
    }

    func run() throws {
        let inputs = paths.map(Paths.url)
        let reporter = Reporter(verbose: options.verbose)
        do {
            let output = options.outputURL.map { options.planner.resolve($0, avoiding: inputs) }
                ?? options.planner.plan(input: inputs[0], ext: "zip", protecting: inputs)
            try ArchiveBackend.create(inputs, at: output)
            reporter.record(nil, outputs: [output])
        } catch {
            reporter.failure(nil, error)
        }
        try reporter.finish()
    }
}
