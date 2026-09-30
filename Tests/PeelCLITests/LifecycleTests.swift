import ConvertKit
import Foundation
import Testing
@testable import PeelCLI
import TestSupport

/// A fake installation in a temp "home", with recorded hooks instead of the real app/login/Finder.
final class FakeInstall: @unchecked Sendable {
    let home: URL
    let services: URL
    let apps: URL
    let prefix: URL
    var running = false
    var opened: [String] = []
    var launched: [String] = []
    var quits = 0
    var events: [String] = []

    init() throws {
        home = try Fixtures.tempDir()
        services = home.appendingPathComponent("Library/Services")
        apps = home.appendingPathComponent("Applications")
        prefix = home.appendingPathComponent(".local")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Fixtures.makeExecutable(at: prefix.appendingPathComponent("bin/peel"), script: "echo 0.3.0")
    }

    var cli: URL { prefix.appendingPathComponent("bin/peel") }
    var app: URL { apps.appendingPathComponent("Peel.app") }

    func installApp(version: String = "0.3.0") throws {
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "dev.peel.app", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    func installQuickActions() throws {
        for kind in QuickActionKind.allCases {
            try WorkflowGenerator.write(kind, peel: cli, into: services)
        }
    }

    func record(_ values: [String: String]) throws {
        try KeyValueFile(values).write(to: PeelSupport.installRecord(home: home))
    }

    var environment: LifecycleEnvironment {
        LifecycleEnvironment(
            home: home, services: services, defaultAppDir: apps, cli: cli,
            isAppRunning: { self.running },
            quitApp: { self.quits += 1; self.running = false; self.events.append("quit") },
            launchApp: { self.launched.append($0.path); self.running = true },
            openURL: { url in
                self.opened.append(url.absoluteString)
                self.events.append(url.absoluteString)
                if FileManager.default.fileExists(atPath: PeelSupport.appState(home: self.home).path) {
                    self.events.append("stale-state")   // the CLI should clear it so only a fresh answer counts
                }
                if url.absoluteString == "peel://login/off" {
                    try? KeyValueFile(["login": "off", "version": "0.3.0"]).write(to: PeelSupport.appState(home: self.home))
                }
                return true
            },
            waitTimeout: 0.2)
    }

    func run(_ arguments: [String]) -> CLIResult {
        LifecycleEnvironment.$current.withValue(environment) { runPeel(arguments) }
    }
}

/// A minimal peel source tree whose install.sh records how it was run.
private func makeSourceTree(in dir: URL, version: String, recordTo record: URL? = nil) throws -> URL {
    let tree = dir.appendingPathComponent("peel-src")
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    try Fixtures.writeText("// swift-tools-version: 6.0\n", to: tree.appendingPathComponent("Package.swift"))
    try Fixtures.writeText(version + "\n", to: tree.appendingPathComponent("VERSION"))
    var script = "echo \"ran norecord=${PEEL_NO_RECORD:-0} prefix=${PREFIX:-}\" >> \"$(dirname \"$0\")/../install.log\""
    if let record {   // like the real install.sh: record where it ran from, unless told not to
        script += "\n[ \"${PEEL_NO_RECORD:-0}\" = 1 ] || { mkdir -p \"\(record.deletingLastPathComponent().path)\"; "
            + "printf 'source=%s\\nversion=\(version)\\n' \"$(cd \"$(dirname \"$0\")\" && pwd)\" > \"\(record.path)\"; }"
    }
    try Fixtures.makeExecutable(at: tree.appendingPathComponent("install.sh"), script: script)
    return tree
}

@Suite struct LifecycleTests {
    @Test func statusReportsTheInstall() throws {
        let fake = try FakeInstall()
        try fake.installApp()
        try fake.installQuickActions()
        try fake.record(["source": "/src/peel", "prefix": fake.prefix.path, "version": "0.3.0"])
        try KeyValueFile(["login": "on", "version": "0.3.0"]).write(to: PeelSupport.appState(home: fake.home))
        fake.running = true
        let result = fake.run(["status"])
        #expect(result.code == 0)
        #expect(result.stdout.contains("peel \(PeelVersion.current)"))
        #expect(result.stdout.contains("quick actions:  5 of 5 installed"))
        #expect(result.stdout.contains("Peel.app (0.3.0), running"))
        #expect(result.stdout.contains("open at login:  on"))
        #expect(result.stdout.contains("source:         /src/peel"))
    }

    @Test func statusOnABareInstall() throws {
        let fake = try FakeInstall()
        let result = fake.run(["status"])
        #expect(result.code == 0)
        #expect(result.stdout.contains("quick actions:  0 of 5 installed"))
        #expect(result.stdout.contains("app:            not installed"))
        #expect(result.stdout.contains("source:         not recorded"))
    }

    @Test func updateFromADirectoryRunsItsInstaller() throws {
        let fake = try FakeInstall()
        try fake.record(["prefix": fake.prefix.path, "version": "0.3.0"])
        let tree = try makeSourceTree(in: fake.home, version: "0.3.1")
        let result = fake.run(["update", tree.path])
        #expect(result.code == 0)
        let log = try String(contentsOf: fake.home.appendingPathComponent("install.log"), encoding: .utf8)
        #expect(log.contains("norecord=0 prefix=\(fake.prefix.path)"))
        #expect(result.stdout.contains("0.3.0 -> 0.3.1"))
    }

    @Test func updateFromAnArchiveDoesNotRecordTheTempDir() throws {
        let fake = try FakeInstall()
        try fake.record(["source": "/src/peel", "version": "0.3.0"])
        let tree = try makeSourceTree(in: fake.home, version: "0.3.1", recordTo: PeelSupport.installRecord(home: fake.home))
        let archive = fake.home.appendingPathComponent("peel-0.3.1.tar.gz")
        try ArchiveBackend.create([tree], at: archive)
        let result = fake.run(["update", archive.path])
        #expect(result.code == 0)
        let logs = try FileManager.default.contentsOfDirectory(atPath: fake.home.path).filter { $0 == "install.log" }
        #expect(logs.isEmpty)   // the extracted tree's log went to its temp parent, not ours
        #expect(KeyValueFile.read(PeelSupport.installRecord(home: fake.home))?["source"] == "/src/peel")
        #expect(KeyValueFile.read(PeelSupport.installRecord(home: fake.home))?["version"] == "0.3.1")
    }

    @Test func updateRelaunchesARunningApp() throws {
        let fake = try FakeInstall()
        try fake.installApp()
        fake.running = true
        let tree = try makeSourceTree(in: fake.home, version: "0.3.1")
        #expect(fake.run(["update", tree.path]).code == 0)
        #expect(fake.quits == 1)
        #expect(fake.launched == [fake.app.path])
    }

    @Test func updateWithoutARecordedSourceExplains() throws {
        let fake = try FakeInstall()
        let result = fake.run(["update"])
        #expect(result.code == 1)
        #expect(result.stderr.contains("no source recorded"))
        #expect(result.stderr.contains("git clone https://github.com/00mkp/peel.git"))
    }

    @Test func updateWithAMissingSourceExplains() throws {
        let fake = try FakeInstall()
        try fake.record(["source": "/nonexistent/peel"])
        let result = fake.run(["update"])
        #expect(result.code == 1)
        #expect(result.stderr.contains("the recorded source is gone"))
    }

    @Test func updateRejectsThingsThatArentPeel() throws {
        let fake = try FakeInstall()
        let other = fake.home.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        #expect(fake.run(["update", other.path]).stderr.contains("does not look like a peel source tree"))
        let rar = try Fixtures.writeText("x", to: fake.home.appendingPathComponent("x.rar"))
        let result = fake.run(["update", rar.path])
        #expect(result.code == 2)
        #expect(result.stderr.contains(".tar.gz"))
    }

    @Test func uninstallRemovesExactlyPeelsFiles() throws {
        let fake = try FakeInstall()
        try fake.installApp()
        try fake.installQuickActions()
        try fake.record(["source": "/src/peel", "prefix": fake.prefix.path, "app_dir": fake.apps.path])
        let theirs = try Fixtures.writeText("keep", to: fake.services.appendingPathComponent("Other.workflow"))
        let neighbour = try Fixtures.writeText("keep", to: fake.prefix.appendingPathComponent("bin/other-tool"))
        fake.running = true
        let result = fake.run(["uninstall"])
        #expect(result.code == 0)
        #expect(fake.opened.contains("peel://login/off"))
        #expect(fake.quits >= 1)
        #expect(!FileManager.default.fileExists(atPath: fake.app.path))
        #expect(!FileManager.default.fileExists(atPath: fake.cli.path))
        #expect(WorkflowGenerator.installedBundles(in: fake.services).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: PeelSupport.directory(home: fake.home).path))
        #expect(FileManager.default.fileExists(atPath: theirs.path))
        #expect(FileManager.default.fileExists(atPath: neighbour.path))
        #expect(result.stdout.contains("/src/peel"))   // tells you the source checkout was left alone
    }

    @Test func uninstallNeverDeletesAnAppThatIsntPeel() throws {
        let fake = try FakeInstall()
        let contents = fake.app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.other"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        _ = fake.run(["uninstall"])
        #expect(FileManager.default.fileExists(atPath: fake.app.path))
    }

    @Test func appSubcommands() throws {
        let fake = try FakeInstall()
        try fake.installApp()
        #expect(fake.run(["app", "start"]).code == 0)
        #expect(fake.launched == [fake.app.path])
        #expect(fake.run(["app", "panel"]).code == 0)
        #expect(fake.opened.last == "peel://panel")
        _ = fake.run(["app", "login", "off"])
        #expect(fake.opened.last == "peel://login/off")
        #expect(fake.run(["app", "stop"]).code == 0)
        #expect(fake.quits == 1)
        #expect(fake.run(["app", "login", "maybe"]).code == 2)
    }

    @Test func appStartWhenNotInstalled() throws {
        let fake = try FakeInstall()
        let result = fake.run(["app", "start"])
        #expect(result.code == 1)
        #expect(result.stderr.contains("not installed"))
    }

    // Review I1: never delete a "peel" that isn't peel.
    @Test func uninstallLeavesAForeignPeelBinaryAlone() throws {
        let fake = try FakeInstall()
        try Fixtures.makeExecutable(at: fake.cli, script: "echo 'some other tool'")
        try fake.record(["prefix": fake.prefix.path])
        let result = fake.run(["uninstall"])
        #expect(FileManager.default.fileExists(atPath: fake.cli.path))
        #expect(result.stderr.contains("isn't peel"))
    }

    // Review I2: failures are reported and exit 1.
    @Test func uninstallReportsWhatItCouldNotRemove() throws {
        let fake = try FakeInstall()
        try fake.record(["prefix": fake.prefix.path])
        let bin = fake.prefix.appendingPathComponent("bin")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bin.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path) }
        let result = fake.run(["uninstall"])
        #expect(result.code == 1)
        #expect(result.stderr.contains("could NOT remove"))
        #expect(!result.stdout.contains("peel: uninstalled"))
    }

    // Review I3: Open at Login is turned off (confirmed fresh) before the app quits.
    @Test func uninstallTurnsLoginOffBeforeQuitting() throws {
        let fake = try FakeInstall()
        try fake.installApp()
        // A stale state file already saying "off" must not count as confirmation.
        try KeyValueFile(["login": "off"]).write(to: PeelSupport.appState(home: fake.home))
        fake.running = true
        _ = fake.run(["uninstall"])
        #expect(fake.events.prefix(2) == ["peel://login/off", "quit"])
        #expect(!fake.events.contains("stale-state"))
    }

    @Test func uninstallTwiceIsHarmless() throws {
        let fake = try FakeInstall()
        try fake.record(["prefix": fake.prefix.path])
        #expect(fake.run(["uninstall"]).code == 0)
        let second = fake.run(["uninstall"])
        #expect(second.code == 0)
        #expect(second.stdout.contains("nothing to remove"))
    }

    // Review minor 2: an archive update puts the previous source back even if its installer recorded itself.
    @Test func archiveUpdateRestoresThePreviousSource() throws {
        let fake = try FakeInstall()
        try fake.record(["source": "/src/peel", "version": "0.3.0"])
        let tree = try makeSourceTree(in: fake.home.appendingPathComponent("x"), version: "0.3.1")
        // this installer ignores PEEL_NO_RECORD and records its own (temp) directory
        try Fixtures.makeExecutable(at: tree.appendingPathComponent("install.sh"), script: """
            mkdir -p "\(PeelSupport.directory(home: fake.home).path)"
            printf 'source=%s\\n' "$(cd "$(dirname "$0")" && pwd)" > "\(PeelSupport.installRecord(home: fake.home).path)"
            """)
        let archive = fake.home.appendingPathComponent("peel.tar.gz")
        try ArchiveBackend.create([tree], at: archive)
        #expect(fake.run(["update", archive.path]).code == 0)
        #expect(KeyValueFile.read(PeelSupport.installRecord(home: fake.home))?["source"] == "/src/peel")
    }

    // Review minor 5: 'app stop' only claims success if the app really quit.
    @Test func appStopChecksItQuit() throws {
        let fake = try FakeInstall()
        fake.running = true
        var env = fake.environment
        env.quitApp = { }   // refuses to quit
        let result = LifecycleEnvironment.$current.withValue(env) { runPeel(["app", "stop"]) }
        #expect(result.code == 1)
        #expect(!result.stdout.contains("✓ Peel quit"))
    }
}
