import ConvertKit
import Foundation

/// What each Finder Quick Action does with the selected files.
struct QuickActionHandler {
    let ui: QuickActionUI
    let runner: ActionRunner
    let locator: ToolLocator

    init(ui: QuickActionUI, runner: ActionRunner, locator: ToolLocator) {
        self.ui = ui
        self.runner = runner
        self.locator = locator
    }

    func handle(_ kind: QuickActionKind, files: [URL]) -> Int32 {
        guard !files.isEmpty else {
            ui.alert("Select one or more files in Finder first.", copyable: nil)
            return 1
        }
        let formats = files.map { FileFormat(url: $0) }
        switch kind {
        case .convert:
            return convert(files)
        case .merge:
            guard files.count >= 2, formats.allSatisfy({ $0 == .pdf }) else {
                ui.alert("Merge PDFs needs two or more PDF files.", copyable: nil)
                return 1
            }
            return report(runner.run(.pdfMerge, on: files), verb: "Merged", grouped: true)
        case .split:
            guard formats.allSatisfy({ $0 == .pdf }) else {
                ui.alert("Split PDF works on PDF files.", copyable: nil)
                return 1
            }
            return report(runner.run(.pdfSplit(ranges: nil), on: files), verb: "Split")
        case .extractHere:
            guard formats.allSatisfy({ $0?.category == .archive }) else {
                ui.alert("Extract Here works on archives (zip, tar, tar.gz, gz, rar, 7z).", copyable: nil)
                return 1
            }
            return report(runner.run(.extract, on: files), verb: "Extracted", noun: "archives")
        case .zip:
            return report(runner.run(.zip, on: files), verb: "Zipped", grouped: true)
        }
    }

    private func convert(_ files: [URL]) -> Int32 {
        let entries = ActionCatalog.entries(for: files, locator: locator).filter {
            if case .convert = $0.kind { return true }
            return false
        }
        guard !entries.isEmpty else {
            ui.alert("peel can't convert this selection — these files have no format in common to convert to.", copyable: nil)
            return 1
        }
        let ordered = entries.filter(\.isAvailable) + entries.filter { !$0.isAvailable }
        func label(_ entry: CatalogEntry) -> String {
            guard case let .convert(target) = entry.kind else { return entry.title }
            return entry.isAvailable
                ? target.rawValue
                : "\(target.rawValue) — needs \(entry.missing.map(\.tool.rawValue).joined(separator: ", "))"
        }
        let subject = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        guard let choice = ui.choose(prompt: "Convert \(subject) to:", items: ordered.map(label)),
              let entry = ordered.first(where: { label($0) == choice }),
              case let .convert(target) = entry.kind else { return 0 }
        guard entry.isAvailable else {
            showMissing(entry.missing)
            return 1
        }
        return report(runner.run(.convert(to: target, options: ConvertOptions()), on: files), verb: "Converted")
    }

    private func showMissing(_ missing: [MissingTool]) {
        var message = missing.map(\.explanation).joined(separator: "\n")
        if locator.homebrew == nil { message += "\n\n" + ToolLocator.homebrewMissingNote }
        ui.alert(message, copyable: ActionCatalog.installCommand(for: missing))
    }

    /// `grouped`: one job over the whole selection (merge, zip) — failures aren't pinned on the first
    /// file. `noun`: what several outputs are called ("archives" for extract, else "files").
    private func report(_ outcomes: [ActionOutcome], verb: String, grouped: Bool = false, noun: String = "files") -> Int32 {
        let outputs = outcomes.flatMap { (try? $0.result.get()) ?? [] }
        let failures = outcomes.compactMap { outcome -> (URL?, Error)? in
            if case let .failure(error) = outcome.result { return (outcome.input, error) }
            return nil
        }
        if failures.isEmpty {
            if outputs.count == 1 {
                ui.notify("\(verb) → \(outputs[0].lastPathComponent)")
            } else {
                ui.notify(noun == "files" ? "\(verb) into \(outputs.count) files" : "\(verb) \(outputs.count) \(noun)")
            }
            return 0
        }
        let missing = failures.compactMap { failure -> MissingTool? in
            guard case let .missingTool(name, _)? = failure.1 as? PeelError, let tool = Tool(rawValue: name) else { return nil }
            return MissingTool(tool: tool)
        }
        if let first = missing.first {
            showMissing([first])
            return 1
        }
        let lines = failures.prefix(10).map { input, error in
            let message = (error as? PeelError)?.errorDescription ?? error.localizedDescription
            return grouped ? message : "\(input?.lastPathComponent ?? "selection"): \(message)"
        }
        let header = outputs.isEmpty ? "peel couldn't finish:" : "\(verb) \(outputs.count) \(noun), but some failed:"
        ui.alert(([header] + lines).joined(separator: "\n"), copyable: nil)
        return 1
    }
}
