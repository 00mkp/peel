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

    public init(inputName: String, outputs: [URL], message: String?, cancelled: Bool) {
        self.inputName = inputName
        self.outputs = outputs
        self.message = message
        self.cancelled = cancelled
    }

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
    /// Keep the menu-bar panel open when clicking elsewhere (for dragging files in from Finder).
    @Published public var panelPinned = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var results: [ResultRow] = []
    @Published public private(set) var tools: [ToolStatus] = []
    @Published public private(set) var homebrew: URL?
    @Published public private(set) var launchAtLogin: Bool
    /// Why the last Open at Login change failed, if it did.
    @Published public private(set) var loginItemError: String?
    @Published public private(set) var loginItemNeedsApproval = false

    private let makeLocator: () -> ToolLocator
    private let loginItem: LoginItem
    private var token: CancelToken?

    public init(locator: @escaping () -> ToolLocator = { .standard }, loginItem: LoginItem = SystemLoginItem()) {
        makeLocator = locator
        self.loginItem = loginItem
        launchAtLogin = loginItem.isEnabled
        refreshTools()
    }

    public func setLaunchAtLogin(_ on: Bool) {
        do {
            try loginItem.setEnabled(on)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change Open at Login: " +
                ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        refreshLoginItem()
        if loginItemNeedsApproval {
            loginItemError = "Allow Peel in System Settings → General → Login Items to finish turning this on."
        }
    }

    /// Re-reads Open at Login (it can be changed in System Settings while Peel runs).
    public func refreshLoginItem() {
        launchAtLogin = loginItem.isEnabled
        loginItemNeedsApproval = loginItem.needsApproval
    }

    public var availableEntries: [CatalogEntry] { entries.filter(\.isAvailable) }
    public var unavailableEntries: [CatalogEntry] { entries.filter { !$0.isAvailable } }

    /// "PDF", "HEIC", "TAR.GZ", "Folder" — what the file list shows next to each name.
    public static func typeLabel(for url: URL) -> String {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
            return "Folder"
        }
        if let format = FileFormat(url: url) { return format.fileExtension.uppercased() }
        let ext = OutputPlanner.splitName(url.lastPathComponent).ext
        return ext.isEmpty ? "File" : ext.uppercased()
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
        results = []
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
        guard let kind = selection, options.hasRequiredInput(for: kind) else { return nil }
        do {
            _ = try options.action(for: kind, files: files)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public var canRun: Bool {
        guard let kind = selection else { return false }
        // hasRequiredInput is checked on its own because validationMessage is nil for empty fields.
        return !isRunning && !files.isEmpty && selectedEntry?.isAvailable == true
            && options.hasRequiredInput(for: kind) && validationMessage == nil
    }

    public var installHelp: InstallHelp? {
        guard let entry = selectedEntry, !entry.isAvailable else { return nil }
        return InstallHelp(missing: entry.missing, command: ActionCatalog.installCommand(for: entry.missing),
                           homebrewMissing: homebrew == nil)
    }

    public func run() async {
        guard canRun, let kind = selection, let action = try? options.action(for: kind, files: files) else { return }
        _ = await perform(action)
    }

    /// Runs a wheel action with default options. The files and action show in the panel too.
    /// Returns nil (and does nothing) when a job is already running or the action needs input.
    public func runQuick(_ kind: ActionKind, on urls: [URL]) async -> [ResultRow]? {
        guard !isRunning, let action = WheelMenu.action(for: kind) else { return nil }
        files = []
        add(urls)
        selection = kind
        return await perform(action)
    }

    private func perform(_ action: PeelAction) async -> [ResultRow] {
        let files = self.files
        let runner = ActionRunner(planner: OutputPlanner(force: force), locator: makeLocator())
        let token = CancelToken()
        self.token = token
        isRunning = true
        let outcomes = await Task.detached { runner.run(action, on: files, cancel: token) }.value
        let rows = outcomes.map(ResultRow.init)
        results = rows
        isRunning = false
        self.token = nil
        return rows
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
