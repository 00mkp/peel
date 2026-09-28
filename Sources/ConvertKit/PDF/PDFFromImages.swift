import CoreGraphics
import Foundation

extension PDFBackend {
    /// One page per image; each page is the image's pixel size in points.
    public static func fromImages(_ inputs: [URL], to output: URL, locator: ToolLocator = .standard) throws {
        try AtomicOutput.write(to: output) { temp in
            guard let context = CGContext(temp as CFURL, mediaBox: nil, nil) else { throw PeelError.writeFailed(output) }
            for input in inputs {
                let image = try ImageBackend.load(input, locator: locator)
                var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                context.beginPage(mediaBox: &box)
                context.draw(image, in: box)
                context.endPage()
            }
            context.closePDF()
        }
    }
}
