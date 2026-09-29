import Foundation

/// Something peel can do, with its options.
public enum PeelAction: Equatable, Sendable {
    case convert(to: FileFormat, options: ConvertOptions)
    case pdfMerge
    case pdfSplit(ranges: PageRange?)
    case pdfExtract(pages: PageRange)
    case pdfDelete(pages: PageRange)
    case pdfRotate(degrees: Int, pages: PageRange?)
    case mediaCompress(targetBytes: Int?)
    case mediaTrim(from: Double, until: Double)
    case mediaGif(fps: Int, width: Int)
    case mediaAudio(to: FileFormat)
    case extract
    case zip

    public var kind: ActionKind {
        switch self {
        case let .convert(target, _): return .convert(target)
        case .pdfMerge: return .pdfMerge
        case .pdfSplit: return .pdfSplit
        case .pdfExtract: return .pdfExtract
        case .pdfDelete: return .pdfDelete
        case .pdfRotate: return .pdfRotate
        case .mediaCompress: return .mediaCompress
        case .mediaTrim: return .mediaTrim
        case .mediaGif: return .mediaGif
        case .mediaAudio: return .mediaAudio
        case .extract: return .extract
        case .zip: return .zip
        }
    }
}

public struct ActionOutcome {
    /// The input this outcome is about (the first input for merge/zip).
    public let input: URL?
    public let result: Result<[URL], Error>

    public var isCancelled: Bool {
        if case let .failure(error) = result, (error as? PeelError) == .cancelled { return true }
        return false
    }
}

/// Runs an action for the Quick Actions and the app. Outputs go next to their inputs, named as the
/// CLI names them; inputs and this run's earlier outputs are never overwritten.
public struct ActionRunner {
    public var planner: OutputPlanner
    public var locator: ToolLocator

    public init(planner: OutputPlanner = OutputPlanner(), locator: ToolLocator = .standard) {
        self.planner = planner
        self.locator = locator
    }

    public func run(_ action: PeelAction, on files: [URL], cancel: CancelToken = CancelToken()) -> [ActionOutcome] {
        // Tools started while running belong to `cancel`, so Cancel stops them (and only them).
        cancel.activate { perform(action, on: files, cancel: cancel) }
    }

    private func perform(_ action: PeelAction, on files: [URL], cancel: CancelToken) -> [ActionOutcome] {
        var tools = ActionCatalog.requirements(for: action.kind, files: files)
        if case .mediaCompress(targetBytes: .some) = action { tools.append(.ffprobe) }
        // Merge and zip are one job over the whole selection: early exits report one outcome.
        let isGrouped = action == .pdfMerge || action == .zip
        func failAll(_ error: Error) -> [ActionOutcome] {
            isGrouped ? [ActionOutcome(input: files.first, result: .failure(error))]
                    : files.map { ActionOutcome(input: $0, result: .failure(error)) }
        }
        if let missing = tools.first(where: { locator.find($0) == nil }) {
            return failAll(PeelError.missingTool(name: missing.rawValue, installHint: missing.installHint))
        }
        if cancel.isCancelled { return failAll(PeelError.cancelled) }

        switch action {
        case let .convert(target, options):
            return Converter(planner: planner, locator: locator)
                .convert(files, to: target, options: options, isCancelled: { cancel.isCancelled })
                .map { ActionOutcome(input: $0.input, result: $0.result) }
        case .pdfMerge:
            return [grouped(files, cancel: cancel) {
                guard files.count >= 2 else { throw PeelError.invalidArgument("merge needs at least 2 PDFs") }
                let out = planner.plan(input: files[0], suffix: "-merged", ext: "pdf", protecting: files)
                try PDFBackend.merge(files, to: out)
                return [out]
            }]
        case .zip:
            return [grouped(files, cancel: cancel) {
                let out = planner.plan(input: files[0], ext: "zip", protecting: files)
                try ArchiveBackend.create(files, at: out)
                return [out]
            }]
        case let .pdfSplit(ranges):
            return eachFile(files, cancel: cancel) { file, protected in
                var written: [URL] = []
                let outputs = try PDFBackend.split(file, ranges: ranges, isCancelled: { cancel.isCancelled }) { group in
                    let out = planner.plan(input: file, suffix: "-" + PDFBackend.pageLabel(for: group), ext: "pdf",
                                           protecting: protected + written)
                    written.append(out)
                    return out
                }
                return outputs
            }
        case let .pdfExtract(pages):
            return eachFile(files, cancel: cancel) { file, protected in
                try single(file, suffix: "-extract", ext: "pdf", protecting: protected) { try PDFBackend.extract(file, pages: pages, to: $0) }
            }
        case let .pdfDelete(pages):
            return eachFile(files, cancel: cancel) { file, protected in
                try single(file, suffix: "-deleted", ext: "pdf", protecting: protected) { try PDFBackend.delete(file, pages: pages, to: $0) }
            }
        case let .pdfRotate(degrees, pages):
            return eachFile(files, cancel: cancel) { file, protected in
                try single(file, suffix: "-rotated", ext: "pdf", protecting: protected) {
                    try PDFBackend.rotate(file, degrees: degrees, pages: pages, to: $0)
                }
            }
        case let .mediaCompress(targetBytes):
            return eachFile(files, cancel: cancel) { file, protected in
                let source = FileFormat(url: file)
                let ext = (source == .mov || source == .mkv) ? source!.fileExtension : "mp4"
                return try single(file, suffix: "-compressed", ext: ext, protecting: protected) {
                    try MediaBackend.compress(file, to: $0, targetBytes: targetBytes, locator: locator)
                }
            }
        case let .mediaTrim(from, until):
            return eachFile(files, cancel: cancel) { file, protected in
                try single(file, suffix: "-trimmed", ext: OutputPlanner.splitName(file.lastPathComponent).ext, protecting: protected) {
                    try MediaBackend.trim(file, to: $0, from: from, until: until, locator: locator)
                }
            }
        case let .mediaGif(fps, width):
            return eachFile(files, cancel: cancel) { file, protected in
                try single(file, suffix: "", ext: "gif", protecting: protected) {
                    try MediaBackend.gif(file, to: $0, fps: fps, width: width, locator: locator)
                }
            }
        case let .mediaAudio(format):
            return eachFile(files, cancel: cancel) { file, protected in
                try single(file, suffix: "", ext: format.fileExtension, protecting: protected) {
                    try MediaBackend.convert(file, to: $0, format: format, locator: locator)
                }
            }
        case .extract:
            return eachFile(files, cancel: cancel) { file, protected in
                [try ArchiveBackend.extract(file, planner: planner, locator: locator, protecting: protected)]
            }
        }
    }

    /// One output next to `file`.
    private func single(_ file: URL, suffix: String, ext: String, protecting: [URL],
                        _ write: (URL) throws -> Void) throws -> [URL] {
        let out = planner.plan(input: file, suffix: suffix, ext: ext, protecting: protecting)
        try write(out)
        return [out]
    }

    /// Runs `body` per file, stopping once cancelled; `protected` is every input plus earlier outputs.
    private func eachFile(_ files: [URL], cancel: CancelToken,
                          _ body: (_ file: URL, _ protected: [URL]) throws -> [URL]) -> [ActionOutcome] {
        var produced: [URL] = []
        return files.map { file in
            if cancel.isCancelled { return ActionOutcome(input: file, result: .failure(PeelError.cancelled)) }
            let result = Result { () throws -> [URL] in
                guard FileManager.default.fileExists(atPath: file.path) else { throw PeelError.fileNotFound(file) }
                return try body(file, files + produced)
            }.mapError { error -> Error in cancel.isCancelled ? PeelError.cancelled : error }
            produced += (try? result.get()) ?? []
            return ActionOutcome(input: file, result: result)
        }
    }

    /// One outcome for an action over the whole selection (merge, zip).
    private func grouped(_ files: [URL], cancel: CancelToken, _ body: () throws -> [URL]) -> ActionOutcome {
        let result = Result { () throws -> [URL] in
            for file in files where !FileManager.default.fileExists(atPath: file.path) { throw PeelError.fileNotFound(file) }
            return try body()
        }.mapError { error -> Error in cancel.isCancelled ? PeelError.cancelled : error }
        return ActionOutcome(input: files.first, result: result)
    }
}
