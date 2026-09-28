import ConvertKit
import Foundation

/// Writes Automator "Run Shell Script" services that hand Finder's selection to `peel quick-action`.
enum WorkflowGenerator {
    /// Info.plist key marking a bundle as peel's own (uninstall removes only these).
    static let infoKey = "PeelQuickAction"

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func script(for kind: QuickActionKind, peel: URL, testLog: URL? = nil, testChoice: String? = nil) -> String {
        var lines = ["P=\(shellQuote(peel.path))"]
        if let testLog { lines.append("export PEEL_QUICK_ACTION_LOG=\(shellQuote(testLog.path))") }
        if let testChoice { lines.append("export PEEL_QUICK_ACTION_CHOICE=\(shellQuote(testChoice))") }
        lines += [
            "if [ ! -x \"$P\" ]; then",
            "  \"${PEEL_OSASCRIPT:-/usr/bin/osascript}\" -e 'display dialog \"The peel command-line tool was not found. Re-run install.sh from the peel folder.\" buttons {\"OK\"} default button 1 with title \"Peel\" with icon caution'",
            "  exit 1",
            "fi",
            "exec \"$P\" quick-action \(kind.rawValue) \"$@\"",
        ]
        return lines.joined(separator: "\n")
    }

    /// Writes (or atomically replaces) one workflow bundle; returns its URL.
    @discardableResult
    static func write(_ kind: QuickActionKind, peel: URL, into directory: URL,
                      testLog: URL? = nil, testChoice: String? = nil) throws -> URL {
        let bundle = directory.appendingPathComponent(kind.bundleName, isDirectory: true)
        let command = script(for: kind, peel: peel, testLog: testLog, testChoice: testChoice)
        try AtomicOutput.write(to: bundle) { temp in
            let contents = temp.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try plistData(document(command: command)).write(to: contents.appendingPathComponent("document.wflow"))
            try plistData(info(for: kind)).write(to: contents.appendingPathComponent("Info.plist"))
        }
        return bundle
    }

    /// Bundles in `directory` that peel installed.
    static func installedBundles(in directory: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return items.filter { bundle in
            guard bundle.pathExtension == "workflow",
                  let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return false
            }
            return plist[infoKey] != nil
        }
    }

    private static func plistData(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    private static func info(for kind: QuickActionKind) -> [String: Any] {
        [
            "NSServices": [[
                "NSMenuItem": ["default": kind.menuTitle],
                "NSMessage": "runWorkflowAsService",
                "NSRequiredContext": ["NSApplicationIdentifier": "com.apple.finder"],
                "NSSendFileTypes": ["public.item"],
            ]],
            infoKey: kind.rawValue,
        ]
    }

    private static func document(command: String) -> [String: Any] {
        let action: [String: Any] = [
            "AMAccepts": ["Container": "List", "Optional": true, "Types": ["com.apple.cocoa.path"]],
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": ["COMMAND_STRING": [:], "CheckedForUserDefaultShell": [:], "inputMethod": [:],
                                      "shell": [:], "source": [:]] as [String: Any],
            "AMProvides": ["Container": "List", "Types": ["com.apple.cocoa.string"]],
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": ["COMMAND_STRING": command, "CheckedForUserDefaultShell": true, "inputMethod": 1,
                                 "shell": "/bin/zsh", "source": ""] as [String: Any],
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": false,
            "CanShowWhenRun": true,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": UUID().uuidString,
            "OutputUUID": UUID().uuidString,
            "UUID": UUID().uuidString,
            "UnlocalizedApplications": ["Automator"],
            "isViewVisible": 1,
        ]
        return [
            "AMApplicationBuild": "534",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [["action": action, "isViewVisible": 1] as [String: Any]],
            "connectors": [:] as [String: Any],
            "workflowMetaData": [
                "applicationBundleIDsByPath": [:] as [String: Any],
                "applicationPaths": [] as [String],
                "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": 0,
                "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": 0,
                "systemImageName": "NSActionTemplate",
                "useAutomaticInputType": 0,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
            ] as [String: Any],
        ]
    }
}
