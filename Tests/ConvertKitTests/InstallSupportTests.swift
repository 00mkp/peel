import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct InstallSupportTests {
    @Test func versionMatchesTheVersionFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        #expect(file.trimmingCharacters(in: .whitespacesAndNewlines) == PeelVersion.current)
    }

    @Test func keyValueFileRoundTrip() throws {
        let url = try Fixtures.tempDir().appendingPathComponent("a/b/install.conf")
        var file = KeyValueFile()
        file["source"] = "/Users/me/src/peel = odd"
        file["version"] = "0.3.0"
        try file.write(to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "source=/Users/me/src/peel = odd\nversion=0.3.0\n")
        #expect(KeyValueFile.read(url) == file)
        #expect(KeyValueFile.read(url.appendingPathExtension("missing")) == nil)
    }

    @Test func supportPaths() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(PeelSupport.installRecord(home: home).path == "/Users/x/Library/Application Support/peel/install.conf")
        #expect(PeelSupport.appState(home: home).path == "/Users/x/Library/Application Support/peel/app-state.conf")
    }
}
