import AppKit
import PeelAppCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var compact = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact {
                HStack {
                    Text("Peel").font(.headline)
                    Spacer()
                    Button("Open Window") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                }
            }
            DropArea(targeted: targeted, compact: compact)
            if !model.files.isEmpty {
                FileList()
                Divider()
                ActionPanel()
            }
            if !model.results.isEmpty {
                Divider()
                ResultsList()
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 12 : 16)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.add([url]) }
                }
            }
            return true
        }
    }
}

struct DropArea: View {
    @EnvironmentObject private var model: AppModel
    let targeted: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: compact ? 22 : 30))
            Text("Drop files here").font(.headline)
            Button("Choose Files…") { choose() }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 90 : 130)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

struct FileList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.files.count == 1 ? "1 file" : "\(model.files.count) files").font(.subheadline.bold())
                Spacer()
                Button("Clear") { model.clear() }.buttonStyle(.link)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.files, id: \.self) { url in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 16, height: 16)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { model.remove(url) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 110)
        }
    }
}

struct ResultsList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Results").font(.subheadline.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.results) { row in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: row.succeeded ? "checkmark.circle.fill"
                                  : row.cancelled ? "slash.circle" : "xmark.octagon.fill")
                                .foregroundStyle(row.succeeded ? Color.green : row.cancelled ? Color.secondary : Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.inputName).lineLimit(1).truncationMode(.middle)
                                if let message = row.message {
                                    Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                                } else if row.cancelled {
                                    Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(row.outputs.map(\.lastPathComponent).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if !row.outputs.isEmpty {
                                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting(row.outputs) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }
}
