import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct AtomicOutputTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".peel-") }
    }

    @Test func movesResultIntoPlace() throws {
        let dest = dir.appendingPathComponent("out.txt")
        try AtomicOutput.write(to: dest) { temp in try Data("hi".utf8).write(to: temp) }
        #expect(try String(contentsOf: dest, encoding: .utf8) == "hi")
        #expect(try leftovers().isEmpty)
    }

    @Test func failureLeavesNothingBehind() throws {
        struct Boom: Error {}
        let dest = dir.appendingPathComponent("out.txt")
        #expect(throws: Boom.self) {
            try AtomicOutput.write(to: dest) { temp in
                try Data("partial".utf8).write(to: temp)
                throw Boom()
            }
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(try leftovers().isEmpty)
    }

    @Test func createsMissingParentFolders() throws {
        let dest = dir.appendingPathComponent("a/b/out.txt")
        try AtomicOutput.write(to: dest) { temp in try Data("x".utf8).write(to: temp) }
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func replacesExistingDestination() throws {
        let dest = dir.appendingPathComponent("out.txt")
        try Data("old".utf8).write(to: dest)
        try AtomicOutput.write(to: dest) { temp in try Data("new".utf8).write(to: temp) }
        #expect(try String(contentsOf: dest, encoding: .utf8) == "new")
    }

    @Test func bodyThatWritesNothingFails() {
        #expect(throws: PeelError.self) {
            try AtomicOutput.write(to: dir.appendingPathComponent("out.txt")) { _ in }
        }
    }

    // Checkpoint 1 I2: even with --force, a folder is never replaced by a file (or vice versa).
    @Test func refusesToReplaceAFolderWithAFile() throws {
        let folder = dir.appendingPathComponent("My Files")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: folder.appendingPathComponent("doc.txt"))
        #expect(throws: PeelError.self) {
            try AtomicOutput.write(to: folder) { temp in try Data("zip".utf8).write(to: temp) }
        }
        #expect(try String(contentsOf: folder.appendingPathComponent("doc.txt"), encoding: .utf8) == "keep")
        #expect(try leftovers().isEmpty)
    }

    @Test func failedBodyKeepsExistingDestination() throws {
        struct Boom: Error {}
        let dest = dir.appendingPathComponent("out.txt")
        try Data("old".utf8).write(to: dest)
        #expect(throws: Boom.self) { try AtomicOutput.write(to: dest) { _ in throw Boom() } }
        #expect(try String(contentsOf: dest, encoding: .utf8) == "old")
    }
}
