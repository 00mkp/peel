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
        abstract: "Add peel actions to Finder's right-click menu (Quick Actions).")

    @Option(help: .hidden) var dir: String?
    @Option(help: .hidden) var peelPath: String?
    @Option(help: .hidden) var testLog: String?
    @Option(help: .hidden) var testChoice: String?

    func run() throws {
        let directory = dir.map(Paths.url) ?? QuickActionPaths.services
        let peel = peelPath.map(Paths.url) ?? QuickActionPaths.currentPeel
        var installed = 0
        var failed = 0
        for kind in QuickActionKind.allCases {
            do {
                try WorkflowGenerator.write(kind, peel: peel, into: directory,
                                            testLog: testLog.map(Paths.url), testChoice: testChoice)
                Console.out("✓ \(kind.menuTitle)")
                installed += 1
            } catch {
                failed += 1
                let message = (error as? PeelError)?.errorDescription ?? error.localizedDescription
                Console.err("✗ \(kind.menuTitle): \(message)")
            }
        }
        if dir == nil { QuickActionPaths.refreshServicesMenu() }
        if installed > 0 {
            Console.out("Right-click files in Finder → Quick Actions → peel - …")
            Console.out("(under Services instead? switch them on in System Settings → General → Login Items & Extensions → Finder)")
        }
        if failed > 0 { throw ExitCode(1) }
    }
}

struct UninstallQuickActions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-quick-actions",
        abstract: "Remove peel's Finder Quick Actions.")

    @Option(help: .hidden) var dir: String?

    func run() throws {
        let directory = dir.map(Paths.url) ?? QuickActionPaths.services
        let bundles = WorkflowGenerator.installedBundles(in: directory)
        for bundle in bundles {
            try FileManager.default.removeItem(at: bundle)
            Console.out("✓ removed \(bundle.deletingPathExtension().lastPathComponent)")
        }
        if bundles.isEmpty { Console.out("no peel Quick Actions installed") }
        if dir == nil { QuickActionPaths.refreshServicesMenu() }
    }
}

struct QuickActionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quick-action",
        abstract: "Run a Finder Quick Action (called by the installed workflows).",
        shouldDisplay: false)

    @Argument(help: "convert, merge-pdfs, split-pdf, extract-here or zip") var kind: QuickActionKind
    @Argument(help: "Selected files.") var files: [String] = []

    func run() throws {
        let environment = ProcessInfo.processInfo.environment
        let ui: QuickActionUI = environment["PEEL_QUICK_ACTION_LOG"].map {
            LogUI(log: URL(fileURLWithPath: $0), choice: environment["PEEL_QUICK_ACTION_CHOICE"])
        } ?? OsascriptUI()
        let locator = ToolLocator.standard
        // The handler has already told the person about any failure (dialog/notification); exiting
        // non-zero would make Automator show a second, blank error.
        _ = QuickActionHandler(ui: ui, runner: ActionRunner(locator: locator), locator: locator)
            .handle(kind, files: files.map(Paths.url))
    }
}
