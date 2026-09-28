import Foundation
import Testing
@testable import ConvertKit
import TestSupport

// Checkpoint 2 M3 / checkpoint 3 I5: legacy Windows encodings must decode correctly.
@Suite struct TextFileTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func file(_ bytes: [UInt8]) throws -> URL {
        let url = dir.appendingPathComponent("t.txt")
        try Data(bytes).write(to: url)
        return url
    }

    @Test func utf16WithBOM() throws {
        let data = try #require("héllo wörld".data(using: .utf16))
        #expect(try TextFile.read(try file(Array(data))) == "héllo wörld")
    }

    @Test func windows1252Punctuation() throws {
        #expect(try TextFile.read(try file([0x93, 0x68, 0x69, 0x94, 0x20, 0x80, 0x35])) == "\u{201C}hi\u{201D} €5")
    }

    @Test func utf8BOMIsDropped() throws {
        #expect(try TextFile.read(try file([0xEF, 0xBB, 0xBF, 0x68, 0x69])) == "hi")
    }

    @Test func latin1StillWorks() throws {
        #expect(try TextFile.read(try file([0x63, 0x61, 0x66, 0xE9])) == "café")
    }
}
