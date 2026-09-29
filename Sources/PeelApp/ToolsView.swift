import ConvertKit
import PeelAppCore
import SwiftUI

/// Optional tool status — the app's `peel doctor`.
struct ToolsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LoginToggle()
            Divider()
            Text("Optional tools").font(.headline)
            Text("PDF tools, most image formats, subtitles, zip and tar work without them.")
                .font(.caption).foregroundStyle(.secondary)
            row(name: "Homebrew", path: model.homebrew, detail: "installs the tools below",
                command: nil, missingNote: ToolLocator.homebrewMissingNote)
            ForEach(model.tools) { status in
                row(name: status.tool.rawValue, path: status.path, detail: status.tool.enables,
                    command: status.tool.installHint, missingNote: nil)
            }
            HStack {
                Spacer()
                Button("Re-check") { model.refreshTools() }
            }
        }
    }

    private func row(name: String, path: URL?, detail: String, command: String?, missingNote: String?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: path == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(path == nil ? Color.red : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).bold()
                // Installed: where it is. Missing: what it adds (or, for Homebrew, where to get it).
                Text(path?.path ?? missingNote ?? "adds \(detail)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if path == nil, let command {
                Button("Copy \"\(command)\"") { copyToPasteboard(command) }
            }
        }
    }
}

/// "Open at Login" switch shared by Settings and the menu-bar popover.
struct LoginToggle: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.loginItemError {
                Text(error).font(.caption).foregroundStyle(model.loginItemNeedsApproval ? .orange : .red)
            }
            if model.loginItemNeedsApproval {
                Button("Open Login Items Settings") { SystemLoginItem.openSettings() }
            }
        }
    }
}
