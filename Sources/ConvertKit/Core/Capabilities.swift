import Foundation

public enum Backend: String, Sendable {
    case pdf, image, media, archive, subtitle
}

/// One supported `from → to` conversion, which backend performs it, and which optional tools it needs.
public struct Conversion: Equatable, Sendable {
    public let from: FileFormat
    public let to: FileFormat
    public let backend: Backend
    public let tools: [Tool]
}

/// The single source of truth for what converts to what. `peel formats`, routing, and future GUI menus read it.
public enum Capabilities {
    static let imageInputs: [FileFormat] = [.jpg, .png, .heic, .tiff, .bmp, .gif, .webp, .avif, .svg]
    static let imageOutputs: [FileFormat] = [.jpg, .png, .heic, .tiff, .bmp, .gif, .webp, .avif]
    static let videoFormats: [FileFormat] = [.mp4, .mov, .mkv, .webm, .avi, .wmv]
    static let audioFormats: [FileFormat] = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
    static let subtitleFormats: [FileFormat] = [.srt, .vtt]

    public static let all: [Conversion] = build()

    public static func conversion(from: FileFormat, to: FileFormat) -> Conversion? {
        all.first { $0.from == from && $0.to == to }
    }

    public static func targets(for format: FileFormat) -> [FileFormat] {
        all.filter { $0.from == format }.map(\.to)
    }

    public static func missingTools(for conversion: Conversion, locator: ToolLocator = .standard) -> [Tool] {
        conversion.tools.filter { locator.find($0) == nil }
    }

    private static func build() -> [Conversion] {
        var list: [Conversion] = []
        func add(_ from: FileFormat, _ to: FileFormat, _ backend: Backend, _ tools: [Tool] = []) {
            list.append(Conversion(from: from, to: to, backend: backend, tools: tools))
        }
        for from in imageInputs {
            let inputTools: [Tool] = from == .svg ? [.rsvgConvert] : []
            for to in imageOutputs {
                var tools = inputTools
                if to == .webp { tools.append(.cwebp) }
                if to == .avif { tools.append(.avifenc) }
                add(from, to, .image, tools)
            }
            add(from, .pdf, .pdf, inputTools)
        }
        for to: FileFormat in [.png, .jpg, .txt] { add(.pdf, to, .pdf) }
        add(.txt, .pdf, .pdf)
        for from in videoFormats {
            for to in videoFormats + [.gif] + audioFormats where to != from { add(from, to, .media, [.ffmpeg]) }
        }
        for to: FileFormat in [.mp4, .mov, .webm] { add(.gif, to, .media, [.ffmpeg]) }
        for from in audioFormats {
            for to in audioFormats where to != from { add(from, to, .media, [.ffmpeg]) }
        }
        for from in subtitleFormats {
            for to in subtitleFormats + [.txt] where to != from { add(from, to, .subtitle) }
        }
        return list
    }
}
