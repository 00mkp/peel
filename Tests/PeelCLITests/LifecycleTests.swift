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

    init() throws {
        home = try Fixtures.tempDir()
        services = home.appendingPathComponent("Library/Services")
        apps = home.appendingPathComponent("Applications")
        prefix = home.appendingPathComponent(".local")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Fixtures.writeText("#!/bin/sh\n", to: prefix.appendingPathComponent("bin/peel"))
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
            quitApp: { self.quits += 1; self.running = false },
            launchApp: { self.launched.append($0.path); self.running = true },
            openURL: { url in
                self.opened.append(url.absoluteString)
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
private func makeSourceTree(in dir: URL, version: String) throws -> URL {
    let tree = dir.appendingPathComponent("peel-src")
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    try Fixtures.writeText("// swift-tools-version: 6.0\n", to: tree.appendingPathComponent("Package.swift"))
    try Fixtures.writeText(version + "\n", to: tree.appendingPathComponent("VERSION"))
    try Fixtures.makeExecutable(at: tree.appendingPathComponent("install.sh"),
                                script: "echo \"ran norecord=${PEEL_NO_RECORD:-0} prefix=${PREFIX:-}\" >> \"$(dirname \"$0\")/../install.log\"")
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
        let tree = try makeSourceTree(in: fake.home, version: "0.3.1")
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
}
