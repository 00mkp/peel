import Foundation
import UniformTypeIdentifiers

/// Broad family a format belongs to; decides which backend and tools apply.
public enum FormatCategory: String, CaseIterable, Sendable {
    case image, document, video, audio, subtitle, archive
}

/// Every file format peel knows about.
public enum FileFormat: String, CaseIterable, Sendable {
    case jpg, png, heic, tiff, bmp, gif, webp, avif, svg
    case pdf, txt
    case mp4, mov, mkv, webm, avi, wmv
    case mp3, m4a, wav, flac, ogg, opus, aiff, wma
    case srt, vtt
    case zip, tar, tgz, tbz2, txz, gz, rar
    case sevenZip = "7z"

    public var category: FormatCategory {
        switch self {
        case .jpg, .png, .heic, .tiff, .bmp, .gif, .webp, .avif, .svg: return .image
        case .pdf, .txt: return .document
        case .mp4, .mov, .mkv, .webm, .avi, .wmv: return .video
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma: return .audio
        case .srt, .vtt: return .subtitle
        case .zip, .tar, .tgz, .tbz2, .txz, .gz, .rar, .sevenZip: return .archive
        }
    }

    /// Extension written for this format (no leading dot).
    public var fileExtension: String {
        switch self {
        case .tgz: return "tar.gz"
        case .tbz2: return "tar.bz2"
        case .txz: return "tar.xz"
        default: return rawValue
        }
    }

    private static let aliases: [String: FileFormat] = [
        "jpeg": .jpg, "jpe": .jpg, "tif": .tiff, "heif": .heic, "aif": .aiff, "m4v": .mp4,
        "text": .txt, "tar.gz": .tgz, "tar.bz2": .tbz2, "tbz": .tbz2, "tar.xz": .txz,
    ]

    private static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz"]

    /// Parses a user-typed format name: "jpeg", "JPG", ".png", "tar.gz".
    public init?(name: String) {
        var key = name.lowercased()
        if key.hasPrefix(".") { key.removeFirst() }
        guard let format = FileFormat(rawValue: key) ?? FileFormat.aliases[key] else { return nil }
        self = format
    }

    /// Detects a file's format from its name, falling back to the system type database
    /// (so e.g. `notes.md` counts as plain text).
    public init?(url: URL) {
        let filename = url.lastPathComponent.lowercased()
        if let compound = FileFormat.compoundExtensions.first(where: { filename.hasSuffix("." + $0) }) {
            self.init(name: compound)
            return
        }
        let ext = url.pathExtension
        guard !ext.isEmpty else { return nil }
        if let format = FileFormat(name: ext) {
            self = format
            return
        }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        let fallbacks: [(UTType, FileFormat)] = [
            (.jpeg, .jpg), (.png, .png), (.heic, .heic), (.tiff, .tiff), (.bmp, .bmp), (.gif, .gif),
            (.pdf, .pdf), (.mpeg4Movie, .mp4), (.quickTimeMovie, .mov), (.mp3, .mp3), (.wav, .wav),
            (.aiff, .aiff), (.zip, .zip), (.plainText, .txt),
        ]
        guard let match = fallbacks.first(where: { type.conforms(to: $0.0) }) else { return nil }
        self = match.1
    }
}
