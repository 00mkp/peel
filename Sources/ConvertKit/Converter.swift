import Foundation

public struct ConvertOptions: Equatable, Sendable {
    public var image: ImageOptions
    /// Resolution for PDF → image.
    public var dpi: Int

    public init(image: ImageOptions = ImageOptions(), dpi: Int = 300) {
        self.image = image
        self.dpi = dpi
    }
}

public struct ConvertOutcome {
    public let input: URL
    public let result: Result<[URL], Error>
}

/// Routes "convert these files to X" to the right backend, one outcome per input.
public struct Converter {
    public var planner: OutputPlanner
    public var locator: ToolLocator

    public init(planner: OutputPlanner = OutputPlanner(), locator: ToolLocator = .standard) {
        self.planner = planner
        self.locator = locator
    }

    /// Several images → pdf become one combined PDF; everything else converts file by file.
    /// `output` is a file for a single result, or a folder (created if needed) when there are several inputs.
    public func convert(_ inputs: [URL], to target: FileFormat, options: ConvertOptions = ConvertOptions(),
                        output: URL? = nil, isCancelled: () -> Bool = { false }) -> [ConvertOutcome] {
        if target == .pdf, inputs.count > 1, inputs.allSatisfy({ FileFormat(url: $0)?.category == .image }) {
            return [ConvertOutcome(input: inputs[0], result: Result { try combineImages(inputs, output: output) })]
        }
        let perFileOutput = inputs.count > 1 ? output.map(Self.asDirectory) : output
        // Never write over any input, or over an output this run already produced — even with --force.
        var produced: [URL] = []
        return inputs.map { input in
            if isCancelled() { return ConvertOutcome(input: input, result: .failure(PeelError.cancelled)) }
            let result = Result {
                try convertOne(input, to: target, options: options, output: perFileOutput, protecting: inputs + produced)
            }.mapError { error -> Error in isCancelled() ? PeelError.cancelled : error }
            produced += (try? result.get()) ?? []
            return ConvertOutcome(input: input, result: result)
        }
    }

    static func asDirectory(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path, isDirectory: true)
    }

    /// Checks the input exists, is recognized, and can become `target` with the installed tools.
    private func check(_ input: URL, to target: FileFormat) throws -> (FileFormat, Conversion) {
        guard FileManager.default.fileExists(atPath: input.path) else { throw PeelError.fileNotFound(input) }
        guard let source = FileFormat(url: input) else { throw PeelError.unknownFormat(input) }
        guard let conversion = Capabilities.conversion(from: source, to: target) else {
            throw PeelError.unsupportedConversion(from: source.rawValue, to: target.rawValue)
        }
        for tool in conversion.tools { _ = try locator.require(tool) }
        return (source, conversion)
    }

    private func combineImages(_ inputs: [URL], output: URL?) throws -> [URL] {
        for input in inputs { _ = try check(input, to: .pdf) }
        let out = planner.plan(input: inputs[0], ext: "pdf", output: output, protecting: inputs)
        try PDFBackend.fromImages(inputs, to: out, locator: locator)
        return [out]
    }

    private func convertOne(_ input: URL, to target: FileFormat, options: ConvertOptions, output: URL?,
                            protecting: [URL]) throws -> [URL] {
        let (source, conversion) = try check(input, to: target)
        let ext = target.fileExtension
        func single(_ write: (URL) throws -> Void) throws -> [URL] {
            let out = planner.plan(input: input, ext: ext, output: output, protecting: protecting)
            try write(out)
            return [out]
        }
        switch (conversion.backend, source, target) {
        case (.pdf, .pdf, .txt):
            return try single { try PDFBackend.text(input, to: $0) }
        case (.pdf, .pdf, _):
            let folder = output.map(Self.asDirectory)
            return try PDFBackend.toImages(input, format: target, dpi: options.dpi) { page in
                planner.plan(input: input, suffix: "-p\(page)", ext: ext, output: folder, protecting: protecting)
            }
        case (.pdf, .txt, _):
            return try single { try PDFBackend.fromText(input, to: $0) }
        case (.pdf, _, _):
            return try single { try PDFBackend.fromImages([input], to: $0, locator: locator) }
        case (.image, _, _):
            return try single { try ImageBackend.convert(input, to: $0, format: target, options: options.image, locator: locator) }
        case (.media, _, _):
            return try single { try MediaBackend.convert(input, to: $0, format: target, locator: locator) }
        case (.subtitle, _, _):
            return try single { try SubtitleBackend.convert(input, to: $0, format: target) }
        case (.archive, _, _):
            throw PeelError.unsupportedConversion(from: source.rawValue, to: target.rawValue)
        }
    }
}
