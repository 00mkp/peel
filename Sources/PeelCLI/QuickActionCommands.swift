import ArgumentParser
import ConvertKit
import Foundation

enum QuickActionPaths {
    static var services: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services", isDirectory: true)
    }

    /// The running peel executable, symlinks resolved (what the workflows should call).
    static var currentPeel: URL {
        URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath()
    }

    /// Makes Finder notice added/removed services right away.
    static func refreshServicesMenu() {
        _ = try? ProcessRunner.run(URL(fileURLWithPath: "/System/Library/CoreServices/pbs"), ["-update"])
    }
}

struct InstallQuickActions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-quick-actions",
        abstract: "Add Peel actions to Finder's right-click menu (Quick Actions).")

    @Option(help: .hidden) var dir: String?
    @Option(help: .hidden) var peelPath: String?
    @Option(help: .hidden) var testLog: String?
    @Option(help: .hidden) var testChoice: String?

    func run() throws {
        let directory = dir.map(Paths.url) ?? QuickActionPaths.services
        let peel = peelPath.map(Paths.url) ?? QuickActionPaths.currentPeel
        for kind in QuickActionKind.allCases {
            try WorkflowGenerator.write(kind, peel: peel, into: directory,
                                        testLog: testLog.map(Paths.url), testChoice: testChoice)
            Console.out("✓ \(kind.menuTitle)")
        }
        if dir == nil { QuickActionPaths.refreshServicesMenu() }
        Console.out("Right-click files in Finder → Quick Actions → Peel - …")
    }
}

struct UninstallQuickActions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-quick-actions",
        abstract: "Remove Peel's Finder Quick Actions.")

    @Option(help: .hidden) var dir: String?

    func run() throws {
        let directory = dir.map(Paths.url) ?? QuickActionPaths.services
        let bundles = WorkflowGenerator.installedBundles(in: directory)
        for bundle in bundles {
            try FileManager.default.removeItem(at: bundle)
            Console.out("✓ removed \(bundle.deletingPathExtension().lastPathComponent)")
        }
        if bundles.isEmpty { Console.out("no Peel Quick Actions installed") }
        if dir == nil { QuickActionPaths.refreshServicesMenu() }
    }
}
