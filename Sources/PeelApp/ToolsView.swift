import ConvertKit
import PeelAppCore
import SwiftUI

/// Optional tool status — the app's `peel doctor`.
struct ToolsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Text(path?.path ?? missingNote ?? detail).font(.caption).foregroundStyle(.secondary)
                if path == nil, command != nil { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if path == nil, let command {
                Button("Copy \"\(command)\"") { copyToPasteboard(command) }
            }
        }
    }
}
