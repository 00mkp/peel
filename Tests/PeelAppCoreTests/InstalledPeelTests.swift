import ConvertKit
import Foundation
import Testing
@testable import PeelAppCore
import TestSupport

private func makePeel(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Fixtures.makeExecutable(at: url, script: "echo 0.3.0")
}

@Suite struct InstalledPeelTests {
    @Test func findsTheRecordedCLIFirst() throws {
        let home = try Fixtures.tempDir()
        let prefix = home.appendingPathComponent("opt")
        try makePeel(at: prefix.appendingPathComponent("bin/peel"))
        try makePeel(at: home.appendingPathComponent(".local/bin/peel"))
        try KeyValueFile(["prefix": prefix.path]).write(to: PeelSupport.installRecord(home: home))
        #expect(InstalledPeel.find(home: home) == prefix.appendingPathComponent("bin/peel"))
    }

    @Test func fallsBackToTheDefaultPrefix() throws {
        let home = try Fixtures.tempDir()
        #expect(InstalledPeel.find(home: home) == nil)
        try makePeel(at: home.appendingPathComponent(".local/bin/peel"))
        #expect(InstalledPeel.find(home: home) == home.appendingPathComponent(".local/bin/peel"))
    }

    @Test func readsUpdateCheckResults() {
        #expect(UpdateCheck(exitCode: 0, stdout: "peel: up to date (0.3.0)\n", stderr: "") == .upToDate("0.3.0"))
        #expect(UpdateCheck(exitCode: 0, stdout: "peel: update available: 0.3.0 -> 0.4.0 (2 new commits)\n  run: peel update\n",
                            stderr: "") == .available("0.3.0 -> 0.4.0 (2 new commits)"))
        #expect(UpdateCheck(exitCode: 1, stdout: "", stderr: "peel: can't check for updates: no git checkout\n  clone …\n")
                == .failed("can't check for updates: no git checkout"))
        #expect(UpdateCheck(exitCode: 1, stdout: "", stderr: "") == .failed("the check failed (exit 1)"))
    }
}
