import ArgumentParser
import ConvertKit
import Foundation

extension PageRange: ExpressibleByArgument {
    public init?(argument: String) {
        guard let range = try? PageRange.parse(argument) else { return nil }
        self = range
    }
}

struct PDFCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdf",
        abstract: "Merge, split, extract, delete, rotate and reorder PDF pages.",
        subcommands: [Merge.self, Split.self, Extract.self, Delete.self, Rotate.self, Reorder.self, Text.self, Info.self])
}

extension PDFCommand {
    struct Merge: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Combine PDFs into one, in the order given.")
        @Argument(help: "PDF files to merge (at least 2).") var files: [String]
        @OptionGroup var options: OutputOptions

        func validate() throws {
            guard files.count >= 2 else { throw ValidationError("merge needs at least 2 PDFs") }
        }

        func run() throws {
            let inputs = files.map(Paths.url)
            let reporter = Reporter(verbose: options.verbose)
            do {
                try inputs.forEach(Paths.requireExists)
                let output = options.planner.plan(input: inputs[0], suffix: "-merged", ext: "pdf", output: options.outputURL,
                                                  protecting: inputs)
                try PDFBackend.merge(inputs, to: output)
                reporter.record(inputs[0], outputs: [output])
            } catch {
                reporter.failure(nil, error)
            }
            try reporter.finish()
        }
    }

    struct Split: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Split into one file per page, or one per range.")
        @Argument(help: "PDF to split.") var file: String
        @Option(help: "Ranges, one output file each (e.g. 1-3,7-9). Default: every page separately.")
        var pages: PageRange?
        @OptionGroup var options: OutputOptions

        func run() throws {
            let input = Paths.url(file)
            let reporter = Reporter(verbose: options.verbose)
            do {
                try Paths.requireExists(input)
                let outputs = try PDFBackend.split(input, ranges: pages) { group in
                    options.planner.plan(input: input, suffix: "-" + PDFBackend.pageLabel(for: group), ext: "pdf",
                                         output: options.outputDirectoryURL)
                }
                reporter.record(input, outputs: outputs)
            } catch {
                reporter.failure(input, error)
            }
            try reporter.finish()
        }
    }

    struct Extract: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy selected pages into a new PDF.")
        @Argument(help: "Source PDF.") var file: String
        @Option(help: "Pages to keep, in order (e.g. 2-5).") var pages: PageRange
        @OptionGroup var options: OutputOptions

        func run() throws {
            try runSingle(file, suffix: "-extract", ext: "pdf", options: options) {
                try PDFBackend.extract($0, pages: pages, to: $1)
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove pages.")
        @Argument(help: "Source PDF.") var file: String
        @Option(help: "Pages to remove (e.g. 4,6).") var pages: PageRange
        @OptionGroup var options: OutputOptions

        func run() throws {
            try runSingle(file, suffix: "-deleted", ext: "pdf", options: options) {
                try PDFBackend.delete($0, pages: pages, to: $1)
            }
        }
    }

    struct Rotate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rotate pages clockwise.")
        @Argument(help: "Source PDF.") var file: String
        @Option(name: .customLong("by"), parsing: .unconditional, help: "Degrees: 90, 180, 270 or -90.")
        var degrees: Int
        @Option(help: "Pages to rotate (default: all).") var pages: PageRange?
        @OptionGroup var options: OutputOptions

        func validate() throws {
            guard [90, 180, 270].contains(((degrees % 360) + 360) % 360) else {
                throw ValidationError("--by must be 90, 180, 270 or -90")
            }
        }

        func run() throws {
            try runSingle(file, suffix: "-rotated", ext: "pdf", options: options) {
                try PDFBackend.rotate($0, degrees: degrees, pages: pages, to: $1)
            }
        }
    }

    struct Reorder: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Put pages in a new order (pages left out are dropped).")
        @Argument(help: "Source PDF.") var file: String
        @Option(help: "New order, e.g. 3,1,2,4- or 10-1 to reverse.") var order: PageRange
        @OptionGroup var options: OutputOptions

        func run() throws {
            try runSingle(file, suffix: "-reordered", ext: "pdf", options: options) {
                try PDFBackend.reorder($0, order: order, to: $1)
            }
        }
    }

    struct Text: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Extract the text of a PDF to a .txt file.")
        @Argument(help: "Source PDF.") var file: String
        @OptionGroup var options: OutputOptions

        func run() throws {
            try runSingle(file, suffix: "", ext: "txt", options: options) {
                try PDFBackend.text($0, to: $1)
            }
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show page count, page size and metadata.")
        @Argument(help: "PDF to inspect.") var file: String

        func run() throws {
            let input = Paths.url(file)
            do {
                try Paths.requireExists(input)
                let info = try PDFBackend.info(input)
                let width = info.pageSize.width, height = info.pageSize.height
                Console.out(Paths.display(input))
                Console.out("  pages:      \(info.pageCount)")
                Console.out(String(format: "  page size:  %.0f × %.0f pt (%.2f × %.2f in)", width, height, width / 72, height / 72))
                Console.out("  title:      \(info.title ?? "—")")
                Console.out("  author:     \(info.author ?? "—")")
                Console.out("  encrypted:  \(info.isEncrypted ? "yes" : "no")")
            } catch {
                let reporter = Reporter()
                reporter.failure(input, error)
                try reporter.finish()
            }
        }
    }
}
