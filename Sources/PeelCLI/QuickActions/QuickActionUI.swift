import AppKit
import ConvertKit
import Foundation

/// How a Quick Action talks to the person (no terminal is attached when Finder runs it).
protocol QuickActionUI {
    /// Returns the chosen item, or nil if dismissed.
    func choose(prompt: String, items: [String]) -> String?
    func notify(_ message: String)
    /// A dialog; `copyable` adds a "Copy Command" button that puts that text on the clipboard.
    func alert(_ message: String, copyable: String?)
}

/// Real dialogs and notifications via osascript.
struct OsascriptUI: QuickActionUI {
    static let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    /// An AppleScript string literal.
    static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func run(_ script: String) -> String? {
        guard let result = try? ProcessRunner.run(Self.osascript, ["-e", script]), result.exitCode == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func choose(prompt: String, items: [String]) -> String? {
        let list = "{" + items.map(Self.literal).joined(separator: ", ") + "}"
        let answer = run("choose from list \(list) with title \"peel\" with prompt \(Self.literal(prompt))")
        return answer == nil || answer == "false" ? nil : answer
    }

    func notify(_ message: String) {
        _ = run("display notification \(Self.literal(message)) with title \"peel\"")
    }

    func alert(_ message: String, copyable: String?) {
        let buttons = copyable == nil ? "{\"OK\"}" : "{\"Copy Command\", \"OK\"}"
        let answer = run("display dialog \(Self.literal(message)) buttons \(buttons) default button \"OK\" with title \"peel\" with icon caution")
        if let copyable, answer?.contains("Copy Command") == true {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyable, forType: .string)
        }
    }
}

/// Writes interactions to a file and answers the picker from a fixed choice (tests, scripting).
struct LogUI: QuickActionUI {
    let log: URL
    let choice: String?

    init(log: URL, choice: String?) {
        self.log = log
        self.choice = choice
    }

    private func append(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: log)
        }
    }

    func choose(prompt: String, items: [String]) -> String? {
        append("choose: \(prompt) | \(items.joined(separator: " / "))")
        return choice
    }

    func notify(_ message: String) { append("notify: \(message)") }

    func alert(_ message: String, copyable: String?) { append("alert: \(message) | copy: \(copyable ?? "-")") }
}
