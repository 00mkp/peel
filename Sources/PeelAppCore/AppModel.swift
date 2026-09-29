import ConvertKit
import Foundation

public struct ToolStatus: Identifiable, Equatable, Sendable {
    public let tool: Tool
    public let path: URL?
    public var id: String { tool.rawValue }
}

public struct InstallHelp: Equatable, Sendable {
    public let missing: [MissingTool]
    public let command: String
    public let homebrewMissing: Bool
}

public struct ResultRow: Identifiable, Equatable {
    public let id = UUID()
    public let inputName: String
    public let outputs: [URL]
    /// Failure message (nil on success or cancel).
    public let message: String?
    public let cancelled: Bool

    public var succeeded: Bool { message == nil && !cancelled }

    init(_ outcome: ActionOutcome) {
        inputName = outcome.input?.lastPathComponent ?? "Selection"
        cancelled = outcome.isCancelled
        switch outcome.result {
        case let .success(urls):
            outputs = urls
            message = nil
        case let .failure(error):
            outputs = []
            message = cancelled ? nil : ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// Everything the app's views show and do, without any SwiftUI.
@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var files: [URL] = []
    @Published public private(set) var entries: [CatalogEntry] = []
    @Published public var selection: ActionKind?
    @Published public var options = ActionOptions()
    /// "Overwrite existing files" — never inputs or this run's own outputs.
    @Published public var force = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var results: [ResultRow] = []
    @Published public private(set) var tools: [ToolStatus] = []
    @Published public private(set) var homebrew: URL?

    private let makeLocator: () -> ToolLocator
    private var token: CancelToken?

    public init(locator: @escaping () -> ToolLocator = { .standard }) {
        makeLocator = locator
        refreshTools()
    }

    /// Adding/removing files is ignored while a job runs (the job's files and Cancel stay on screen).
    public func add(_ urls: [URL]) {
        guard !isRunning else { return }
        for url in urls where !files.contains(url) { files.append(url) }
        results = []
        recompute()
    }

    public func remove(_ url: URL) {
        guard !isRunning else { return }
        files.removeAll { $0 == url }
        recompute()
    }

    public func clear() {
        guard !isRunning else { return }
        files = []
        results = []
        recompute()
    }

    public var selectedEntry: CatalogEntry? { entries.first { $0.kind == selection } }

    public var validationMessage: String? {
        guard let kind = selection else { return nil }
        do {
            _ = try options.action(for: kind, files: files)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public var canRun: Bool {
        !isRunning && !files.isEmpty && selectedEntry?.isAvailable == true && validationMessage == nil
    }

    public var installHelp: InstallHelp? {
        guard let entry = selectedEntry, !entry.isAvailable else { return nil }
        return InstallHelp(missing: entry.missing, command: ActionCatalog.installCommand(for: entry.missing),
                           homebrewMissing: homebrew == nil)
    }

    public func run() async {
        guard canRun, let kind = selection, let action = try? options.action(for: kind, files: files) else { return }
        let files = self.files
        let runner = ActionRunner(planner: OutputPlanner(force: force), locator: makeLocator())
        let token = CancelToken()
        self.token = token
        isRunning = true
        let outcomes = await Task.detached { runner.run(action, on: files, cancel: token) }.value
        results = outcomes.map(ResultRow.init)
        isRunning = false
        self.token = nil
    }

    public func cancel() {
        token?.cancel()
    }

    /// Re-checks optional tools (the app calls this whenever it becomes active).
    public func refreshTools() {
        let locator = makeLocator()
        tools = Tool.allCases.map { ToolStatus(tool: $0, path: locator.find($0)) }
        homebrew = locator.homebrew
        recompute()
    }

    private func recompute() {
        entries = ActionCatalog.entries(for: files, locator: makeLocator())
        if let current = selection, !entries.contains(where: { $0.kind == current }) { selection = nil }
        if selection == nil { selection = entries.first(where: \.isAvailable)?.kind }
    }
}
