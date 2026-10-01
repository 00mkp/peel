import AppKit
import ConvertKit
import PeelAppCore

/// About, Check for Updates and Uninstall from the gear menu. Update and Uninstall run the installed
/// `peel` command, so they behave exactly like `peel update` / `peel uninstall` in a terminal.
@MainActor
enum LifecycleActions {
    private static var updating = false

    static func about() {
        let credits = NSAttributedString(
            string: "Converts images, PDFs, audio, video and archives from the menu bar, Finder or the command line.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate(ignoringOtherApps: true)   // an accessory app's panel would open behind the front app
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "peel", .applicationVersion: PeelVersion.current, .version: "", .credits: credits,
        ])
    }

    static func checkForUpdates() {
        guard !updating else {
            alert("peel is already updating", "It restarts by itself when the update is done.")
            return
        }
        guard let peel = requirePeel() else { return }
        run(peel, ["update", "--check"]) { code, out, err in
            switch UpdateCheck(exitCode: code, stdout: out, stderr: err) {
            case let .upToDate(version):
                alert("peel is up to date", "You have the latest version (\(version)).")
            case let .available(summary):
                let answer = alert("An update is available", "\(summary.replacingOccurrences(of: "->", with: "→"))\n\n"
                                   + "peel rebuilds from its source folder (this takes a few minutes) and restarts when it's done.",
                                   buttons: ["Update", "Later"])
                if answer == .alertFirstButtonReturn { update(peel) }
            case let .failed(message):
                alert("Couldn't check for updates", message.prefix(1).uppercased() + message.dropFirst())
            }
        }
    }

    private static func update(_ peel: URL) {
        updating = true
        Notifier.shared.post("Updating peel — it restarts when the new version is ready.") {}
        // On success `peel update` quits this app and launches the new one, which says it was updated.
        run(peel, ["update"]) { code, out, err in
            updating = false
            guard code != 0 else { return }
            let tail = (err + out).split(whereSeparator: \.isNewline).suffix(4).joined(separator: "\n")
            alert("The update didn't finish", "\(tail)\n\nRun “peel update” in Terminal to see everything.")
        }
    }

    static func uninstall() {
        guard let peel = requirePeel() else { return }
        var detail = "This removes peel.app, the Finder Quick Actions, the peel command and peel's settings, "
            + "and turns off Open at Login."
        if let source = KeyValueFile.read(PeelSupport.installRecord())?["source"] {
            detail += "\n\nYour source folder (\(abbreviate(source))) is left in place."
        }
        guard alert("Uninstall peel?", detail, buttons: ["Uninstall", "Cancel"], destructive: true)
                == .alertFirstButtonReturn else { return }
        // On success `peel uninstall` quits this app; we only hear back if something went wrong.
        run(peel, ["uninstall"]) { code, _, err in
            guard code != 0 else { return }
            alert("peel couldn't remove everything", err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: Helpers

    private static func requirePeel() -> URL? {
        if let peel = InstalledPeel.find() { return peel }
        alert("The peel command isn't installed", "Reinstall peel by running ./install.sh in its source folder.")
        return nil
    }

    /// Runs `peel` off the main thread. A plain Process (not ProcessRunner): it must keep running
    /// if `peel` quits this app part-way, as update and uninstall do.
    private static func run(_ peel: URL, _ arguments: [String],
                            then done: @escaping @MainActor (Int32, String, String) -> Void) {
        let out = Pipe(), err = Pipe()
        let process = Process()
        process.executableURL = peel
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        DispatchQueue.global(qos: .userInitiated).async {
            do { try process.run() } catch {
                DispatchQueue.main.async { done(-1, "", error.localizedDescription) }
                return
            }
            // Read both pipes to the end first so a chatty build can't fill one and stall.
            var outData = Data(), errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            let code = process.terminationStatus
            let stdout = String(decoding: outData, as: UTF8.self), stderr = String(decoding: errData, as: UTF8.self)
            DispatchQueue.main.async { done(code, stdout, stderr) }
        }
    }

    @discardableResult
    private static func alert(_ title: String, _ text: String, buttons: [String] = ["OK"],
                              destructive: Bool = false) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        if destructive { alert.buttons.first?.hasDestructiveAction = true }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
