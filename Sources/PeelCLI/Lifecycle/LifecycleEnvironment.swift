import AppKit
import ConvertKit
import Foundation

/// Everything the lifecycle commands touch outside peel's own files — injectable so tests use a fake
/// home and never quit the real app, change the real login item or delete real preferences.
struct LifecycleEnvironment {
    static let appBundleID = "dev.peel.app"

    var home: URL
    var services: URL
    var defaultAppDir: URL
    var cli: URL
    var isAppRunning: () -> Bool
    var quitApp: () -> Void
    var launchApp: (URL) -> Void
    /// Opens a `peel://` URL (LaunchServices starts Peel.app if needed). Returns false if that failed.
    var openURL: (URL) -> Bool
    var deletePreferences: () -> Void
    /// How long to wait for the app to confirm a change through its state file.
    var waitTimeout: TimeInterval

    init(home: URL, services: URL, defaultAppDir: URL, cli: URL,
         isAppRunning: @escaping () -> Bool, quitApp: @escaping () -> Void, launchApp: @escaping (URL) -> Void,
         openURL: @escaping (URL) -> Bool, deletePreferences: @escaping () -> Void = {}, waitTimeout: TimeInterval = 5) {
        self.home = home
        self.services = services
        self.defaultAppDir = defaultAppDir
        self.cli = cli
        self.isAppRunning = isAppRunning
        self.quitApp = quitApp
        self.launchApp = launchApp
        self.openURL = openURL
        self.deletePreferences = deletePreferences
        self.waitTimeout = waitTimeout
    }

    static var live: LifecycleEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let open = URL(fileURLWithPath: "/usr/bin/open")
        func running() -> [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID) }
        return LifecycleEnvironment(
            home: home,
            services: QuickActionPaths.services,
            defaultAppDir: home.appendingPathComponent("Applications", isDirectory: true),
            cli: QuickActionPaths.currentPeel,
            isAppRunning: { !running().isEmpty },
            quitApp: {
                running().forEach { $0.terminate() }
                let deadline = Date().addingTimeInterval(5)
                while !running().isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            },
            launchApp: { app in _ = try? ProcessRunner.run(open, [app.path]) },
            openURL: { url in (try? ProcessRunner.run(open, ["-g", url.absoluteString]))?.exitCode == 0 },
            deletePreferences: { _ = try? ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/defaults"), ["delete", appBundleID]) })
    }

    @TaskLocal static var current: LifecycleEnvironment = .live

    // MARK: Derived

    var record: KeyValueFile { KeyValueFile.read(PeelSupport.installRecord(home: home)) ?? KeyValueFile() }
    var appState: KeyValueFile? { KeyValueFile.read(PeelSupport.appState(home: home)) }

    var appURL: URL {
        let dir = record["app_dir"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultAppDir
        return dir.appendingPathComponent("Peel.app", isDirectory: true)
    }

    /// The installed Peel.app's version, or nil if there is no Peel.app (or the bundle isn't peel's).
    var installedAppVersion: String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Self.appBundleID else { return nil }
        return info["CFBundleShortVersionString"] as? String ?? "?"
    }

    var cliPath: URL {
        record["prefix"].map { URL(fileURLWithPath: $0).appendingPathComponent("bin/peel") } ?? cli
    }

    /// Polls the app's state file until `condition` holds or the timeout passes.
    func waitForAppState(_ condition: (KeyValueFile) -> Bool) -> KeyValueFile? {
        let deadline = Date().addingTimeInterval(waitTimeout)
        repeat {
            if let state = appState, condition(state) { return state }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return nil
    }
}
