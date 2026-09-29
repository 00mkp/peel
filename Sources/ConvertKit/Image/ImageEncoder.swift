import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension FileFormat {
    /// The type ImageIO writes natively for this format, if any.
    public var imageUTType: UTType? {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .gif: return .gif
        default: return nil
        }
    }
}

public enum ImageEncoder {
    /// Writes one image with ImageIO. `quality` is 1–100 (lossy formats only).
    public static func write(_ image: CGImage, to url: URL, type: UTType, quality: Int? = nil) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw PeelError.writeFailed(url)
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(min(max(quality, 1), 100)) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PeelError.writeFailed(url) }
    }

    public static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Draws `image` over opaque white — for formats without transparency (JPEG, BMP).
    public static func flattened(_ image: CGImage) throws -> CGImage {
        guard let space = ImageBackend.rgbSpace(of: image),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw PeelError.invalidArgument("image is too large to process")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let result = context.makeImage() else { throw PeelError.invalidArgument("image is too large to process") }
        return result
    }
}
