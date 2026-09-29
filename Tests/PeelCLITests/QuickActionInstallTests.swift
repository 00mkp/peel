import ConvertKit
import Foundation
import Testing
@testable import PeelCLI
import TestSupport

@Suite struct QuickActionInstallTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func install(peel: String = "/usr/bin/true") -> CLIResult {
        runPeel(["install-quick-actions", "--dir", dir.path, "--peel-path", peel])
    }
    private func command(_ bundle: URL) throws -> String {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/document.wflow"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let actions = plist?["actions"] as? [[String: Any]]
        let action = actions?.first?["action"] as? [String: Any]
        let parameters = action?["ActionParameters"] as? [String: Any]
        return parameters?["COMMAND_STRING"] as? String ?? ""
    }

    @Test func installsFiveValidWorkflows() throws {
        #expect(install().code == 0)
        let bundles = WorkflowGenerator.installedBundles(in: dir).map(\.lastPathComponent).sorted()
        #expect(bundles == QuickActionKind.allCases.map(\.bundleName).sorted())
        for bundle in WorkflowGenerator.installedBundles(in: dir) {
            for file in ["Contents/document.wflow", "Contents/Info.plist"] {
                #expect(try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/plutil"),
                                              ["-lint", bundle.appendingPathComponent(file).path]).exitCode == 0)
            }
        }
    }

    @Test func scriptCallsPeelWithTheActionName() throws {
        _ = install()
        let script = try command(dir.appendingPathComponent(QuickActionKind.merge.bundleName))
        #expect(script.contains("'/usr/bin/true'"))
        #expect(script.contains("quick-action merge-pdfs \"$@\""))
        #expect(try ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-n", "-c", script]).exitCode == 0)
    }

    @Test func menuTitleInInfoPlist() throws {
        _ = install()
        let info = dir.appendingPathComponent(QuickActionKind.convert.bundleName).appendingPathComponent("Contents/Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any]
        let services = plist?["NSServices"] as? [[String: Any]]
        #expect((services?.first?["NSMenuItem"] as? [String: String])?["default"] == "Peel - Convert To…")
        #expect(plist?[WorkflowGenerator.infoKey] as? String == "convert")
    }

    // Review Focus 5: apostrophes in the peel path are quoted safely.
    @Test func quotesAwkwardPeelPaths() throws {
        let script = WorkflowGenerator.script(for: .zip, peel: URL(fileURLWithPath: "/tmp/it's here/peel"))
        #expect(script.contains("P='/tmp/it'\\''s here/peel'"))
        #expect(try ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-n", "-c", script]).exitCode == 0)
    }

    // Review Focus 1: a moved/deleted peel binary produces a dialog, not silence.
    @Test func missingPeelShowsADialog() throws {
        let script = WorkflowGenerator.script(for: .zip, peel: URL(fileURLWithPath: "/nonexistent/peel"))
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", script, "zsh", "/tmp/x"],
                                           environment: ["PEEL_OSASCRIPT": "/bin/echo"])
        #expect(result.stdout.contains("display dialog"))
        #expect(result.stdout.contains("install.sh"))
    }

    @Test func reinstallReplacesAndUninstallRemovesOnlyPeelWorkflows() throws {
        let other = dir.appendingPathComponent("Other.workflow")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = install(peel: "/usr/bin/true")
        _ = install(peel: "/usr/bin/false")
        #expect(try command(dir.appendingPathComponent(QuickActionKind.zip.bundleName)).contains("'/usr/bin/false'"))
        let result = runPeel(["uninstall-quick-actions", "--dir", dir.path])
        #expect(result.code == 0)
        #expect(WorkflowGenerator.installedBundles(in: dir).isEmpty)
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func testOptionsAreBakedIntoTheScript() throws {
        let script = WorkflowGenerator.script(for: .convert, peel: URL(fileURLWithPath: "/usr/bin/true"),
                                              testLog: URL(fileURLWithPath: "/tmp/log.txt"), testChoice: "jpg")
        #expect(script.contains("export PEEL_QUICK_ACTION_LOG='/tmp/log.txt'"))
        #expect(script.contains("export PEEL_QUICK_ACTION_CHOICE='jpg'"))
    }

    // Checkpoint B I1: after its own dialog the script must exit 0, or Automator adds a blank error.
    @Test func missingPeelDialogIsTheOnlyError() throws {
        let script = WorkflowGenerator.script(for: .zip, peel: URL(fileURLWithPath: "/nonexistent/peel"))
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", script, "zsh", "/tmp/x"],
                                           environment: ["PEEL_OSASCRIPT": "/bin/echo"])
        #expect(result.exitCode == 0)
    }

    // Review Focus 1: a crash inside peel still produces a readable dialog.
    @Test func crashShowsADialog() throws {
        let fake = dir.appendingPathComponent("peel")
        try Fixtures.makeExecutable(at: fake, script: "kill -SEGV $$")
        let script = WorkflowGenerator.script(for: .zip, peel: fake)
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", script, "zsh", "/tmp/x"],
                                           environment: ["PEEL_OSASCRIPT": "/bin/echo"])
        #expect(result.stdout.contains("quit unexpectedly"))
        #expect(result.exitCode == 0)
    }
}
