import ConvertKit
import PeelAppCore
import SwiftUI

struct ActionPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Action", selection: $model.selection) {
                ForEach(model.entries, id: \.kind) { entry in
                    Text(entry.isAvailable
                         ? entry.title
                         : "\(entry.title) — needs \(entry.missing.map(\.tool.rawValue).joined(separator: ", "))")
                        .tag(Optional(entry.kind))
                }
            }
            if let help = model.installHelp {
                InstallHelpView(help: help)
            } else if let kind = model.selection {
                OptionsView(kind: kind)
            }
            if let message = model.validationMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Toggle("Overwrite existing files", isOn: $model.force)
                    .help("Never overwrites the files you dropped.")
                Spacer()
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Run") { Task { await model.run() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canRun)
                }
            }
        }
    }
}

struct OptionsView: View {
    @EnvironmentObject private var model: AppModel
    let kind: ActionKind

    private var hasPDFInput: Bool { model.files.contains { FileFormat(url: $0) == .pdf } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch kind {
            case let .convert(target):
                if [.jpg, .heic, .webp, .avif].contains(target) {
                    TextField("Quality 1–100 (optional)", text: $model.options.quality)
                }
                if target.category == .image {
                    HStack {
                        TextField("Width px (optional)", text: $model.options.width)
                        TextField("Height px (optional)", text: $model.options.height)
                    }
                }
                if hasPDFInput && (target == .png || target == .jpg) {
                    TextField("Resolution (dpi)", text: $model.options.dpi)
                }
            case .pdfSplit:
                TextField("Pages per file, e.g. 1-3,7-9 (blank = every page)", text: $model.options.pages)
            case .pdfExtract:
                TextField("Pages to keep, e.g. 2-5", text: $model.options.pages)
            case .pdfDelete:
                TextField("Pages to delete, e.g. 4,6", text: $model.options.pages)
            case .pdfRotate:
                Picker("Rotate", selection: $model.options.degrees) {
                    Text("90° ↻").tag(90)
                    Text("180°").tag(180)
                    Text("90° ↺").tag(270)
                }
                .pickerStyle(.segmented)
                TextField("Pages (blank = all)", text: $model.options.rotatePages)
            case .mediaCompress:
                TextField("Target size, e.g. 25MB (optional)", text: $model.options.size)
            case .mediaTrim:
                HStack {
                    TextField("From, e.g. 0:10", text: $model.options.from)
                    TextField("To, e.g. 0:45", text: $model.options.to)
                }
            case .mediaGif:
                HStack {
                    TextField("Frames per second", text: $model.options.fps)
                    TextField("Width px", text: $model.options.gifWidth)
                }
            case .mediaAudio:
                Picker("Format", selection: $model.options.audioFormat) {
                    ForEach(ActionOptions.audioFormats, id: \.self) { Text($0.rawValue).tag($0) }
                }
            case .pdfMerge, .extract, .zip:
                EmptyView()
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct InstallHelpView: View {
    let help: InstallHelp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This needs \(help.missing.map(\.tool.rawValue).joined(separator: ", ")), which isn't installed.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            ForEach(help.missing, id: \.tool) { item in
                Text("\(item.tool.rawValue) adds \(item.tool.enables).").font(.caption)
            }
            if help.homebrewMissing, let url = URL(string: "https://brew.sh") {
                Link("Homebrew isn't installed — get it first from brew.sh", destination: url).font(.caption)
            }
            HStack {
                Text(help.command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy Command") { copyToPasteboard(help.command) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            Text("Run it in Terminal, then come back — Peel re-checks automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
