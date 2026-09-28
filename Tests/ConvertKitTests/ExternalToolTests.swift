import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct ExternalToolTests {
    @Test func findsToolsInSearchPaths() throws {
        let dir = try Fixtures.tempDir()
        try Fixtures.makeExecutable(at: dir.appendingPathComponent("ffmpeg"), script: "echo fake")
        let locator = ToolLocator(searchPaths: ["/nonexistent", dir.path])
        #expect(locator.find(.ffmpeg) == dir.appendingPathComponent("ffmpeg"))
        #expect(locator.find(.cwebp) == nil)
    }

    @Test func requireGivesInstallHint() {
        #expect(throws: PeelError.missingTool(name: "unar", installHint: "brew install unar")) {
            try ToolLocator(searchPaths: []).require(.unar)
        }
    }

    @Test func standardLocatorIncludesHomebrewPaths() {
        let paths = ToolLocator.standard.searchPaths
        #expect(paths.contains("/opt/homebrew/bin"))
        #expect(paths.contains("/usr/local/bin"))
    }

    @Test func capturesStdout() throws {
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), ["hello world"])
        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello world\n")
    }

    @Test func checkedRunReportsLastErrorLine() {
        #expect(throws: PeelError.toolFailed(name: "sh", exitCode: 3, lastLine: "second", details: "first\nsecond\n")) {
            try ProcessRunner.runChecked(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo first >&2; echo second >&2; exit 3"])
        }
    }

    @Test func largeOutputDoesNotDeadlock() throws {
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"),
                                           ["-c", "head -c 2000000 /dev/zero | tr '\\0' a; head -c 2000000 /dev/zero | tr '\\0' b >&2"])
        #expect(result.stdout.count == 2_000_000)
        #expect(result.stderr.count == 2_000_000)
    }

    @Test func stdoutCanGoToAFile() throws {
        let out = try Fixtures.tempDir().appendingPathComponent("out.txt")
        try ProcessRunner.runChecked(URL(fileURLWithPath: "/bin/echo"), ["to file"], stdoutTo: out)
        #expect(try String(contentsOf: out, encoding: .utf8) == "to file\n")
    }

    @Test func passesEnvironment() throws {
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo $PEEL_TEST"],
                                           environment: ["PEEL_TEST": "yes"])
        #expect(result.stdout == "yes\n")
    }
}
