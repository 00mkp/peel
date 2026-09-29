import ConvertKit
import Foundation

public struct WheelSlot: Equatable, Identifiable, Sendable {
    public let kind: ActionKind
    public let label: String
    public let systemImage: String
    public var id: String { label }
}

/// The action wheel's contents: available one-step actions for the dragged files.
public enum WheelMenu {
    public static let maxSlots = 6

    static let preferredTargets: [FileFormat] = [.jpg, .png, .pdf, .mp4, .mp3, .m4a, .webp, .heic, .gif, .txt, .vtt, .srt]

    public static func slots(for files: [URL], locator: ToolLocator = .standard) -> [WheelSlot] {
        let sources = Set(files.compactMap { FileFormat(url: $0) })
        let kinds = ActionCatalog.entries(for: files, locator: locator)
            .filter { $0.isAvailable && action(for: $0.kind) != nil }
            .map(\.kind)
            .filter { kind in
                if case let .convert(target) = kind { return !(sources.count == 1 && sources.contains(target)) }
                return true
            }
        let ranked = kinds.filter { $0 != .zip }.sorted { rank($0) < rank($1) }
        var chosen = Array(ranked.prefix(maxSlots - 1))
        if kinds.contains(.zip) { chosen.append(.zip) }
        return chosen.map { WheelSlot(kind: $0, label: label($0), systemImage: symbol($0)) }
    }

    /// The default, option-free action for a kind (nil when it needs input, e.g. page numbers).
    public static func action(for kind: ActionKind) -> PeelAction? {
        switch kind {
        case let .convert(target): return .convert(to: target, options: ConvertOptions())
        case .pdfMerge: return .pdfMerge
        case .pdfSplit: return .pdfSplit(ranges: nil)
        case .pdfRotate: return .pdfRotate(degrees: 90, pages: nil)
        case .mediaCompress: return .mediaCompress(targetBytes: nil)
        case .mediaGif: return .mediaGif(fps: 12, width: 480)
        case .mediaAudio: return .mediaAudio(to: .mp3)
        case .extract: return .extract
        case .zip: return .zip
        case .pdfExtract, .pdfDelete, .mediaTrim: return nil
        }
    }

    static func rank(_ kind: ActionKind) -> Int {
        switch kind {
        case .pdfMerge: return 0
        case .extract: return 1
        case .mediaCompress: return 2
        case .mediaGif: return 3
        case .mediaAudio: return 4
        case .pdfSplit: return 5
        case let .convert(target): return 10 + (preferredTargets.firstIndex(of: target) ?? 30)
        case .pdfRotate: return 60
        default: return 90
        }
    }

    static func label(_ kind: ActionKind) -> String {
        switch kind {
        case let .convert(target): return "→ " + target.rawValue.uppercased()
        case .pdfMerge: return "Merge"
        case .pdfSplit: return "Split"
        case .pdfRotate: return "Rotate 90°"
        case .mediaCompress: return "Compress"
        case .mediaGif: return "GIF"
        case .mediaAudio: return "MP3"
        case .extract: return "Extract"
        case .zip: return "Zip"
        default: return kind.title
        }
    }

    static func symbol(_ kind: ActionKind) -> String {
        switch kind {
        case let .convert(target):
            switch target.category {
            case .image: return "photo"
            case .video: return "film"
            case .audio: return "waveform"
            case .subtitle: return "captions.bubble"
            case .archive: return "archivebox"
            case .document: return target == .pdf ? "doc.richtext" : "text.alignleft"
            }
        case .pdfMerge: return "doc.on.doc"
        case .pdfSplit: return "scissors"
        case .pdfRotate: return "rotate.right"
        case .mediaCompress: return "arrow.down.right.and.arrow.up.left"
        case .mediaGif: return "photo.stack"
        case .mediaAudio: return "waveform"
        case .extract: return "shippingbox"
        case .zip: return "archivebox"
        default: return "circle"
        }
    }
}

/// Notification text for a wheel run.
public enum QuickSummary {
    public static func text(for kind: ActionKind, rows: [ResultRow]) -> String {
        if !rows.isEmpty && rows.allSatisfy(\.cancelled) { return "\(kind.title): cancelled" }
        let failed = rows.filter { !$0.succeeded && !$0.cancelled }
        if let first = failed.first {
            return "\(kind.title): \(failed.count) of \(rows.count) failed — \(first.inputName): \(first.message ?? "failed")"
        }
        let outputs = rows.flatMap(\.outputs)
        if outputs.count == 1 { return "\(kind.title) → \(outputs[0].lastPathComponent)" }
        return "\(kind.title) → \(outputs.count) files"
    }
}
