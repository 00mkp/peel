import ConvertKit
import Foundation

/// The option fields shown in the app, as typed; turned into a PeelAction with validation.
public struct ActionOptions: Equatable, Sendable {
    public var quality = ""
    public var width = ""
    public var height = ""
    public var dpi = "300"
    public var pages = ""
    public var degrees = 90
    public var rotatePages = ""
    public var size = ""
    public var from = ""
    public var to = ""
    public var fps = "12"
    public var gifWidth = "480"
    public var audioFormat: FileFormat = .mp3

    public init() {}

    public static let audioFormats: [FileFormat] = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]

    public func action(for kind: ActionKind, files: [URL]) throws -> PeelAction {
        switch kind {
        case let .convert(target):
            let image = ImageOptions(quality: try optionalInt(quality, in: 1...100, "Quality must be 1–100."),
                                     width: try optionalInt(width, in: 1...100_000, "Width must be a positive number."),
                                     height: try optionalInt(height, in: 1...100_000, "Height must be a positive number."))
            let resolution = try optionalInt(dpi, in: 10...1200, "Resolution must be 10–1200 dpi.") ?? 300
            return .convert(to: target, options: ConvertOptions(image: image, dpi: resolution))
        case .pdfMerge: return .pdfMerge
        case .pdfSplit: return .pdfSplit(ranges: try optionalRange(pages))
        case .pdfExtract: return .pdfExtract(pages: try requiredRange(pages))
        case .pdfDelete: return .pdfDelete(pages: try requiredRange(pages))
        case .pdfRotate:
            guard [90, 180, 270].contains(degrees) else { throw PeelError.invalidArgument("Rotation must be 90, 180 or 270°.") }
            return .pdfRotate(degrees: degrees, pages: try optionalRange(rotatePages))
        case .mediaCompress:
            let trimmed = size.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .mediaCompress(targetBytes: nil) }
            guard let bytes = MediaBackend.parseSize(trimmed) else {
                throw PeelError.invalidArgument("Target size looks like 25MB, 500KB or 1.5GB.")
            }
            return .mediaCompress(targetBytes: bytes)
        case .mediaTrim:
            guard let start = MediaBackend.parseTime(from.trimmingCharacters(in: .whitespaces)),
                  let end = MediaBackend.parseTime(to.trimmingCharacters(in: .whitespaces)) else {
                throw PeelError.invalidArgument("Times look like 90, 1:30 or 01:02:03.5.")
            }
            guard end > start else { throw PeelError.invalidArgument("The end time must be after the start time.") }
            return .mediaTrim(from: start, until: end)
        case .mediaGif:
            return .mediaGif(fps: try optionalInt(fps, in: 1...50, "Frames per second must be 1–50.") ?? 12,
                             width: try optionalInt(gifWidth, in: 16...3840, "GIF width must be 16–3840.") ?? 480)
        case .mediaAudio: return .mediaAudio(to: audioFormat)
        case .extract: return .extract
        case .zip: return .zip
        }
    }

    private func optionalInt(_ text: String, in range: ClosedRange<Int>, _ message: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let value = Int(trimmed), range.contains(value) else { throw PeelError.invalidArgument(message) }
        return value
    }

    private func optionalRange(_ text: String) throws -> PageRange? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : try requiredRange(trimmed)
    }

    private func requiredRange(_ text: String) throws -> PageRange {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw PeelError.invalidArgument("Enter pages, e.g. 1-3,5 or 8-.") }
        guard let range = try? PageRange.parse(trimmed) else {
            throw PeelError.invalidArgument("Pages look like 3, 1-3,5 or 8- (to the end).")
        }
        return range
    }
}
