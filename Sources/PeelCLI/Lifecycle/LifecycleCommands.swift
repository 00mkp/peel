import ArgumentParser
import ConvertKit
import Foundation

/// peel status — what's installed and running.
struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show peel's version and what's installed.")

    func run() throws {
        let env = LifecycleEnvironment.current
        let record = env.record
        Console.out("peel \(PeelVersion.current)")
        Console.out("  cli:            \(env.cliPath.path)")
        Console.out("  source:         \(Self.describeSource(record["source"]))")
        let installed = WorkflowGenerator.installedBundles(in: env.services).count
        Console.out("  quick actions:  \(installed) of \(QuickActionKind.allCases.count) installed")
        if let version = env.installedAppVersion {
            Console.out("  app:            \(env.appURL.path) (\(version)), \(env.isAppRunning() ? "running" : "not running")")
        } else {
            Console.out("  app:            not installed")
        }
        Console.out("  open at login:  \(env.appState?["login"] ?? "unknown (open Peel once)")")
        let locator = ToolLocator.standard
        let missing = Tool.allCases.filter { locator.find($0) == nil }.map(\.rawValue)
        Console.out("  tools:          " + (missing.isEmpty
            ? "all \(Tool.allCases.count) optional tools installed"
            : "missing \(missing.joined(separator: ", ")) (peel doctor for details)"))
    }

    static func describeSource(_ source: String?) -> String {
        guard let source, !source.isEmpty else { return "not recorded" }
        guard FileManager.default.fileExists(atPath: source) else { return "\(source) (missing)" }
        let git = try? ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/git"), ["-C", source, "rev-parse", "--short", "HEAD"])
        if let commit = git?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), git?.exitCode == 0, !commit.isEmpty {
            return "\(source) (git \(commit))"
        }
        return source
    }
}

/// peel update [dir|archive] — pull the recorded source and reinstall, or install from elsewhere.
struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update peel: pull the recorded source, rebuild and reinstall (or install from a directory/archive).")

    @Argument(help: "A peel source directory or .tar.gz/.tgz/.zip archive (default: the recorded source).")
    var from: String?

    func run() throws {
        let code = Self.update(from, env: LifecycleEnvironment.current)
        if code != 0 { throw ExitCode(code) }
    }

    static func update(_ given: String?, env: LifecycleEnvironment) -> Int32 {
        let fm = FileManager.default
        var tree: URL
        var tempDir: URL?
        defer { if let tempDir { try? fm.removeItem(at: tempDir) } }

        if let given {
            let url = Paths.url(given)
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isFolder) else {
                Console.err("peel: no such directory or archive: \(given)")
                return 2
            }
            if isFolder.boolValue {
                tree = url
            } else {
                let name = url.lastPathComponent.lowercased()
                guard [".tar.gz", ".tgz", ".zip"].contains(where: name.hasSuffix) else {
                    Console.err("peel: unsupported archive '\(given)' (need .tar.gz, .tgz or .zip)")
                    return 2
                }
                let temp = fm.temporaryDirectory.appendingPathComponent("peel-update-\(UUID().uuidString)")
                tempDir = temp
                do {
                    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                    tree = try ArchiveBackend.extract(url, into: temp)
                } catch {
                    Console.err("peel: couldn't unpack \(given): \((error as? PeelError)?.errorDescription ?? error.localizedDescription)")
                    return 1
                }
            }
        } else {
            guard let source = env.record["source"], !source.isEmpty else {
                Console.err("peel: no source recorded (the last install came from an archive, or predates this).")
                Console.err("  point update at one:  peel update <dir|archive>")
                Console.err("  or clone and reinstall to record a source for future updates:")
                Console.err("    git clone https://github.com/00mkp/peel.git")
                Console.err("    cd peel && ./install.sh")
                return 1
            }
            tree = URL(fileURLWithPath: source, isDirectory: true)
            guard fm.fileExists(atPath: tree.path) else {
                Console.err("peel: the recorded source is gone: \(source)")
                Console.err("  clone it again and reinstall:")
                Console.err("    git clone https://github.com/00mkp/peel.git")
                Console.err("    cd peel && ./install.sh")
                Console.err("  or point update at a copy:  peel update <dir|archive>")
                return 1
            }
            if fm.fileExists(atPath: tree.appendingPathComponent(".git").path) {
                Console.out("==> Pulling latest in \(tree.path)")
                // --ff-only: never invent a merge commit in the user's checkout.
                let pull = try? ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/git"), ["-C", tree.path, "pull", "--ff-only"])
                guard pull?.exitCode == 0 else {
                    Console.err("peel: git pull failed; resolve it in \(tree.path) and retry")
                    return 1
                }
            } else {
                Console.out("==> \(tree.path) is not a git checkout; installing it as-is")
            }
        }

        let installer = tree.appendingPathComponent("install.sh")
        guard fm.fileExists(atPath: installer.path),
              fm.fileExists(atPath: tree.appendingPathComponent("Package.swift").path),
              fm.fileExists(atPath: tree.appendingPathComponent("VERSION").path) else {
            Console.err("peel: \(tree.path) does not look like a peel source tree")
            return 1
        }

        let record = env.record
        let before = record["version"] ?? PeelVersion.current
        let after = (try? String(contentsOf: tree.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let wasRunning = env.isAppRunning()
        var environment: [String: String] = [:]
        if let prefix = record["prefix"] { environment["PREFIX"] = prefix }
        if let appDir = record["app_dir"] { environment["APP_DIR"] = appDir }
        // An archive unpacks into a temp dir we're about to delete; never record it as the source.
        if tempDir != nil { environment["PEEL_NO_RECORD"] = "1" }

        Console.out("==> Installing from \(tree.path)")
        let result = try? ProcessRunner.run(URL(fileURLWithPath: "/bin/bash"), [installer.path], environment: environment)
        guard let result, result.exitCode == 0 else {
            Console.err("peel: install failed; the previous version may still be in place")
            let tail = (result?.stderr ?? "").split(whereSeparator: \.isNewline).suffix(5)
            tail.forEach { Console.err("  " + $0) }
            return 1
        }
        if tempDir != nil, var updated = KeyValueFile.read(PeelSupport.installRecord(home: env.home)) {
            updated["version"] = after
            try? updated.write(to: PeelSupport.installRecord(home: env.home))
        }
        if wasRunning && env.installedAppVersion != nil {
            env.quitApp()
            env.launchApp(env.appURL)
        }
        Console.out("peel: updated \(before) -> \(after)")
        return 0
    }
}

/// peel uninstall — remove everything peel installed (not your source checkout).
struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove peel: the menu-bar app (and its login item), Finder Quick Actions, the CLI and peel's settings.")

    func run() throws {
        let env = LifecycleEnvironment.current
        let fm = FileManager.default
        let record = env.record
        var removed = 0

        if env.installedAppVersion != nil, env.openURL(URL(string: "peel://login/off")!) {
            _ = env.waitForAppState { $0["login"] == "off" }   // so no dangling login item is left behind
        }
        if env.isAppRunning() { env.quitApp() }

        for bundle in WorkflowGenerator.installedBundles(in: env.services) where (try? fm.removeItem(at: bundle)) != nil {
            removed += 1
        }
        if removed > 0 { Console.out("✓ removed \(removed) Finder Quick Actions") }
        if env.services == QuickActionPaths.services { QuickActionPaths.refreshServicesMenu() }

        if env.installedAppVersion != nil, (try? fm.removeItem(at: env.appURL)) != nil {
            Console.out("✓ removed \(env.appURL.path)")
            removed += 1
        }
        let cli = env.cliPath
        if fm.fileExists(atPath: cli.path), (try? fm.removeItem(at: cli)) != nil {
            Console.out("✓ removed \(cli.path)")
            removed += 1
        }
        let support = PeelSupport.directory(home: env.home)
        if fm.fileExists(atPath: support.path), (try? fm.removeItem(at: support)) != nil {
            Console.out("✓ removed peel's settings (\(support.path))")
            removed += 1
        }
        env.deletePreferences()

        if removed == 0 { Console.out("peel: nothing to remove (already uninstalled)") } else { Console.out("peel: uninstalled") }
        if let source = record["source"], !source.isEmpty {
            Console.out("  your source checkout at \(source) was left in place")
        }
    }
}

/// peel app … — control the menu-bar app from the terminal.
struct AppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Start, stop or control the Peel menu-bar app.",
        subcommands: [Start.self, Stop.self, Panel.self, Login.self])
}

extension AppCommand {
    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Launch the menu-bar app.")
        func run() throws {
            let env = LifecycleEnvironment.current
            guard env.installedAppVersion != nil else {
                Console.err("peel: Peel.app is not installed (expected \(env.appURL.path)) — run ./install.sh from the source")
                throw ExitCode(1)
            }
            env.launchApp(env.appURL)
            Console.out("✓ Peel is running (look for the peel-twist icon in the menu bar)")
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Quit the menu-bar app.")
        func run() throws {
            let env = LifecycleEnvironment.current
            guard env.isAppRunning() else {
                Console.out("Peel isn't running")
                return
            }
            env.quitApp()
            Console.out("✓ Peel quit")
        }
    }

    struct Panel: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open the menu-bar panel.")
        func run() throws {
            guard LifecycleEnvironment.current.openURL(URL(string: "peel://panel")!) else {
                Console.err("peel: couldn't reach Peel.app — is it installed? (peel status)")
                throw ExitCode(1)
            }
        }
    }

    struct Login: ParsableCommand {
        enum Setting: String, ExpressibleByArgument { case on, off }
        static let configuration = CommandConfiguration(abstract: "Turn Open at Login on or off.")
        @Argument(help: "on or off") var setting: Setting

        func run() throws {
            let env = LifecycleEnvironment.current
            guard env.openURL(URL(string: "peel://login/\(setting.rawValue)")!) else {
                Console.err("peel: couldn't reach Peel.app — is it installed? (peel status)")
                throw ExitCode(1)
            }
            let state = env.waitForAppState { [setting.rawValue, "needs-approval"].contains($0["login"] ?? "") }
            switch state?["login"] {
            case setting.rawValue?:
                Console.out("✓ Open at Login is \(setting.rawValue)")
            case "needs-approval"?:
                Console.out("Peel is waiting for approval — allow it in System Settings → General → Login Items")
            default:
                Console.out("requested; open Peel's Settings to check it took effect")
            }
        }
    }
}
