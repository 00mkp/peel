import AppKit
import Foundation
import Testing
@testable import PeelAppCore
import TestSupport

@Suite struct AppIconTests {
    @Test func appIconIsAnOrangeTileWithAWhiteTwist() throws {
        let rep = try #require(NSBitmapImageRep(data: PeelIcon.appIconPNG(pixels: 256)))
        #expect(rep.pixelsWide == 256 && rep.pixelsHigh == 256)
        #expect((rep.colorAt(x: 3, y: 3)?.alphaComponent ?? 1) == 0)          // outside the rounded tile
        let tile = try #require(rep.colorAt(x: 40, y: 128)?.usingColorSpace(NSColorSpace.sRGB))   // tile, clear of the twist
        #expect(tile.redComponent > 0.85 && tile.blueComponent < 0.4)
        var white = 0
        for x in 64..<192 {
            for y in 64..<192 {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.sRGB),
                   c.redComponent > 0.95, c.greenComponent > 0.95, c.blueComponent > 0.95 { white += 1 }
            }
        }
        #expect(white > 500)
    }

    @Test func iconsetHasEverySizeIconutilWants() throws {
        let dir = try Fixtures.tempDir().appendingPathComponent("peel.iconset")
        try PeelIcon.writeIconset(to: dir)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        let expected = [16, 32, 128, 256, 512].flatMap { ["icon_\($0)x\($0).png", "icon_\($0)x\($0)@2x.png"] }.sorted()
        #expect(names == expected)
        let big = try #require(NSBitmapImageRep(data: Data(contentsOf: dir.appendingPathComponent("icon_512x512@2x.png"))))
        #expect(big.pixelsWide == 1024)
    }
}
