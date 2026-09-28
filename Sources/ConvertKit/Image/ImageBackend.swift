import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageOptions: Equatable, Sendable {
    /// 1–100, lossy formats only.
    public var quality: Int?
    public var width: Int?
    public var height: Int?

    public init(quality: Int? = nil, width: Int? = nil, height: Int? = nil) {
        self.quality = quality
        self.width = width
        self.height = height
    }
}

public enum ImageBackend {
    /// Loads the first frame with EXIF orientation applied. SVG is rasterized with rsvg-convert.
    public static func load(_ url: URL, locator: ToolLocator = .standard) throws -> CGImage {
        if FileFormat(url: url) == .svg {
            let rsvg = try locator.require(.rsvgConvert)
            let png = FileManager.default.temporaryDirectory.appendingPathComponent("peel-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: png) }
            try ProcessRunner.runChecked(rsvg, ["-f", "png", "-o", png.path, url.path])
            return try load(png, locator: locator)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw PeelError.unreadableFile(url)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1 {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PeelError.unreadableFile(url) }
            return image
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PeelError.unreadableFile(url)
        }
        return image
    }

    /// Width or height alone: scale to it keeping aspect ratio, never enlarging.
    /// Both: fit inside that box keeping aspect ratio (enlarging allowed).
    public static func targetSize(width: Int, height: Int, options: ImageOptions) -> (width: Int, height: Int) {
        let w = Double(width), h = Double(height)
        let scale: Double
        switch (options.width, options.height) {
        case let (boxW?, boxH?): scale = min(Double(boxW) / w, Double(boxH) / h)
        case let (boxW?, nil): scale = min(Double(boxW) / w, 1)
        case let (nil, boxH?): scale = min(Double(boxH) / h, 1)
        case (nil, nil): scale = 1
        }
        return (max(Int((w * scale).rounded()), 1), max(Int((h * scale).rounded()), 1))
    }

    public static func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PeelError.invalidArgument("image is too large to resize")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw PeelError.invalidArgument("image is too large to resize") }
        return result
    }

    public static func convert(_ input: URL, to output: URL, format: FileFormat,
                               options: ImageOptions = ImageOptions(), locator: ToolLocator = .standard) throws {
        // Fail fast on missing encoders, before any decoding work.
        let encoder: URL?
        switch format {
        case .webp: encoder = try locator.require(.cwebp)
        case .avif: encoder = try locator.require(.avifenc)
        default:
            guard format.imageUTType != nil else {
                throw PeelError.unsupportedConversion(from: input.pathExtension.lowercased(), to: format.rawValue)
            }
            encoder = nil
        }

        var image = try load(input, locator: locator)
        let size = targetSize(width: image.width, height: image.height, options: options)
        if size.width != image.width || size.height != image.height {
            image = try resize(image, width: size.width, height: size.height)
        }
        if (format == .jpg || format == .bmp) && ImageEncoder.hasAlpha(image) {
            image = try ImageEncoder.flattened(image)
        }

        try AtomicOutput.write(to: output) { temp in
            guard let encoder else {
                try ImageEncoder.write(image, to: temp, type: format.imageUTType!, quality: options.quality)
                return
            }
            let png = FileManager.default.temporaryDirectory.appendingPathComponent("peel-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: png) }
            try ImageEncoder.write(image, to: png, type: .png)
            if format == .webp {
                try ProcessRunner.runChecked(encoder, ["-quiet", "-metadata", "icc", "-q", "\(options.quality ?? 85)",
                                                       png.path, "-o", temp.path])
            } else {
                try ProcessRunner.runChecked(encoder, ["-q", "\(options.quality ?? 60)", png.path, temp.path])
            }
        }
    }
}
