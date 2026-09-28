import Foundation

/// A kind of thing peel can do to a selection (options are chosen separately).
public enum ActionKind: Hashable, Sendable {
    case convert(FileFormat)
    case pdfMerge, pdfSplit, pdfExtract, pdfDelete, pdfRotate
    case mediaCompress, mediaTrim, mediaGif, mediaAudio
    case extract, zip

    public var title: String {
        switch self {
        case let .convert(format): return "Convert to \(format.rawValue.uppercased())"
        case .pdfMerge: return "Merge PDFs"
        case .pdfSplit: return "Split PDF"
        case .pdfExtract: return "Extract Pages"
        case .pdfDelete: return "Delete Pages"
        case .pdfRotate: return "Rotate Pages"
        case .mediaCompress: return "Compress Video"
        case .mediaTrim: return "Trim"
        case .mediaGif: return "Make GIF"
        case .mediaAudio: return "Extract Audio"
        case .extract: return "Extract Archive"
        case .zip: return "Zip"
        }
    }
}

/// An optional tool an action needs but that isn't installed.
public struct MissingTool: Equatable, Sendable {
    public let tool: Tool

    public init(tool: Tool) {
        self.tool = tool
    }

    /// "ffmpeg isn't installed (it adds video/audio conversion, …). Install it with: brew install ffmpeg"
    public var explanation: String {
        "\(tool.rawValue) isn't installed (it adds \(tool.enables)). Install it with: \(tool.installHint)"
    }
}

public struct CatalogEntry: Equatable, Sendable {
    public let kind: ActionKind
    public let missing: [MissingTool]

    public var isAvailable: Bool { missing.isEmpty }
    public var title: String { kind.title }
}

/// Which actions fit a selection of files, and whether each can run with the installed tools.
public enum ActionCatalog {
    public static func entries(for files: [URL], locator: ToolLocator = .standard) -> [CatalogEntry] {
        guard !files.isEmpty else { return [] }
        let known = files.compactMap { FileFormat(url: $0) }
        let allKnown = known.count == files.count
        func all(_ category: FormatCategory) -> Bool { allKnown && known.allSatisfy { $0.category == category } }

        var kinds: [ActionKind] = []
        if allKnown && known.allSatisfy({ $0 == .pdf }) {
            if files.count >= 2 { kinds.append(.pdfMerge) }
            kinds += [.pdfSplit, .pdfExtract, .pdfDelete, .pdfRotate]
        }
        if all(.video) {
            kinds.append(.mediaCompress)
            if files.count == 1 { kinds.append(.mediaTrim) }
            kinds += [.mediaGif, .mediaAudio]
        }
        if all(.archive) { kinds.append(.extract) }
        if allKnown, let first = known.first {
            var targets = Capabilities.targets(for: first)
            for format in known.dropFirst() {
                let allowed = Set(Capabilities.targets(for: format))
                targets = targets.filter(allowed.contains)
            }
            kinds += targets.map { .convert($0) }
        }
        kinds.append(.zip)
        return kinds.map { CatalogEntry(kind: $0, missing: missing(requirements(for: $0, files: files), locator: locator)) }
    }

    /// Optional tools an action needs for these files. (`compress` to a target size also needs
    /// ffprobe; ActionRunner adds that once the size is known.)
    public static func requirements(for kind: ActionKind, files: [URL]) -> [Tool] {
        switch kind {
        case let .convert(target):
            var tools: [Tool] = []
            for format in files.compactMap({ FileFormat(url: $0) }) {
                for tool in Capabilities.conversion(from: format, to: target)?.tools ?? [] where !tools.contains(tool) {
                    tools.append(tool)
                }
            }
            return tools
        case .mediaCompress, .mediaTrim, .mediaGif, .mediaAudio:
            return [.ffmpeg]
        case .extract:
            return files.contains { [.rar, .sevenZip].contains(FileFormat(url: $0)) } ? [.unar] : []
        case .pdfMerge, .pdfSplit, .pdfExtract, .pdfDelete, .pdfRotate, .zip:
            return []
        }
    }

    public static func missing(_ tools: [Tool], locator: ToolLocator) -> [MissingTool] {
        tools.filter { locator.find($0) == nil }.map(MissingTool.init(tool:))
    }

    /// One command installing everything missing: "brew install ffmpeg webp".
    public static func installCommand(for missing: [MissingTool]) -> String {
        var formulas: [String] = []
        for item in missing {
            let formula = item.tool.installHint.replacingOccurrences(of: "brew install ", with: "")
            if !formulas.contains(formula) { formulas.append(formula) }
        }
        return "brew install " + formulas.joined(separator: " ")
    }
}
