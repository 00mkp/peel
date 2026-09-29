import ArgumentParser
import ConvertKit
import Foundation

extension FileFormat: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(name: argument)
    }
}

struct Convert: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert files to another format (each file's format is detected automatically).",
        discussion: "Several images converted to pdf become one PDF. Run 'peel formats' to see every conversion.")

    @Argument(help: "Files to convert.") var files: [String]
    @Option(help: "Target format, e.g. jpg, png, webp, pdf, txt, mp4, mp3, gif, vtt.") var to: FileFormat
    @Option(help: "Quality 1-100 for lossy image formats.") var quality: Int?
    @Option(help: "Resize to this width in pixels (keeps aspect ratio, never enlarges).") var width: Int?
    @Option(help: "Resize to this height in pixels (with --width: fit inside the box).") var height: Int?
    @Option(help: "Resolution for PDF → image.") var dpi = 300
    @OptionGroup var options: OutputOptions

    func validate() throws {
        guard !files.isEmpty else { throw ValidationError("give at least one file to convert") }
        if let quality, !(1...100).contains(quality) { throw ValidationError("--quality must be 1-100") }
        if let width, width < 1 { throw ValidationError("--width must be positive") }
        if let height, height < 1 { throw ValidationError("--height must be positive") }
        guard (10...1200).contains(dpi) else { throw ValidationError("--dpi must be 10-1200") }
        guard let output = options.output else { return }
        let target = Paths.url(output)
        let isFolder = OutputPlanner.isDirectory(target)
        let combinesIntoOnePDF = to == .pdf && files.count > 1
            && files.allSatisfy { FileFormat(url: Paths.url($0))?.category == .image }
        // Only a *known, different* format in the name is a mistake: notes.md for txt or "v1.2" are fine.
        let named = isFolder ? nil : FileFormat(url: target)
        if files.count > 1 && !combinesIntoOnePDF {
            if !isFolder && (FileManager.default.fileExists(atPath: target.path) || named != nil) {
                throw ValidationError("with several files, -o must be a folder (end it with / to make one)")
            }
        } else if let named, named != to {
            let ext = OutputPlanner.splitName(target.lastPathComponent).ext
            throw ValidationError("-o ends in .\(ext) but --to is \(to.rawValue); use a .\(to.fileExtension) name or a folder")
        }
    }

    func run() throws {
        if quality != nil && ![.jpg, .heic, .webp, .avif].contains(to) {
            Console.err("note: --quality is ignored for \(to.rawValue) (it only affects jpg, heic, webp and avif)")
        }
        let converter = Converter(planner: options.planner)
        let settings = ConvertOptions(image: ImageOptions(quality: quality, width: width, height: height), dpi: dpi)
        let reporter = Reporter(verbose: options.verbose)
        for outcome in converter.convert(files.map(Paths.url), to: to, options: settings, output: options.outputURL) {
            switch outcome.result {
            case let .success(outputs): reporter.record(outcome.input, outputs: outputs)
            case let .failure(error): reporter.failure(outcome.input, error)
            }
        }
        try reporter.finish(verb: "converted")
    }
}
