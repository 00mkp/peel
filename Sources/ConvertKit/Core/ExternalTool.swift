import Foundation

/// Optional command-line tools peel can use when installed.
public enum Tool: String, CaseIterable, Sendable {
    case ffmpeg, ffprobe, cwebp, avifenc, unar
    case rsvgConvert = "rsvg-convert"

    public var installHint: String {
        switch self {
        case .ffmpeg, .ffprobe: return "brew install ffmpeg"
        case .cwebp: return "brew install webp"
        case .avifenc: return "brew install libavif"
        case .unar: return "brew install unar"
        case .rsvgConvert: return "brew install librsvg"
        }
    }

    /// What installing this tool unlocks (shown by `peel doctor`).
    public var enables: String {
        switch self {
        case .ffmpeg: return "video/audio conversion, trim, compress, GIF"
        case .ffprobe: return "compress --size"
        case .cwebp: return "WebP output"
        case .avifenc: return "AVIF output"
        case .unar: return "RAR and 7z extraction"
        case .rsvgConvert: return "SVG input"
        }
    }
}

/// Finds tools on PATH plus the Homebrew locations (Finder Quick Actions run with a minimal PATH).
public struct ToolLocator: Sendable {
    public var searchPaths: [String]

    public init(searchPaths: [String]) {
        self.searchPaths = searchPaths
    }

    /// PATH plus the Homebrew folders — or exactly `PEEL_TOOL_PATH` (colon-separated) when it is set.
    public static var standard: ToolLocator {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["PEEL_TOOL_PATH"] {
            return ToolLocator(searchPaths: override.split(separator: ":").map(String.init))
        }
        var paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !paths.contains(extra) {
            paths.append(extra)
        }
        return ToolLocator(searchPaths: paths)
    }

    /// Shown whenever a tool is missing and Homebrew itself isn't installed either.
    public static let homebrewMissingNote = "Homebrew isn't installed — get it first from https://brew.sh"

    /// Homebrew's `brew`, if installed.
    public var homebrew: URL? { findExecutable(named: "brew") }

    public func find(_ tool: Tool) -> URL? { findExecutable(named: tool.rawValue) }

    private func findExecutable(named name: String) -> URL? {
        for dir in searchPaths where !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public func require(_ tool: Tool) throws -> URL {
        guard let url = find(tool) else {
            throw PeelError.missingTool(name: tool.rawValue, installHint: tool.installHint)
        }
        return url
    }
}

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    /// Last non-empty stderr line — usually the actual error message.
    public var lastErrorLine: String {
        stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
    }
}

public enum ProcessRunner {
    /// Runs `executable` to completion with an argument array (no shell). Output is captured through
    /// temporary files so large outputs can't deadlock. `stdoutTo` sends stdout to a file instead.
    @discardableResult
    public static func run(_ executable: URL, _ arguments: [String], stdoutTo: URL? = nil,
                           environment: [String: String] = [:]) throws -> ProcessResult {
        let fm = FileManager.default
        let outURL = stdoutTo ?? fm.temporaryDirectory.appendingPathComponent("peel-out-\(UUID().uuidString)")
        let errURL = fm.temporaryDirectory.appendingPathComponent("peel-err-\(UUID().uuidString)")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        defer {
            if stdoutTo == nil { try? fm.removeItem(at: outURL) }
            try? fm.removeItem(at: errURL)
        }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        InterruptCleanup.track(process)
        defer { InterruptCleanup.untrack(process) }
        try process.run()
        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()

        let stdout = stdoutTo == nil ? String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self) : ""
        let stderr = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Like `run`, but throws `PeelError.toolFailed` on a non-zero exit.
    @discardableResult
    public static func runChecked(_ executable: URL, _ arguments: [String], stdoutTo: URL? = nil,
                                  environment: [String: String] = [:]) throws -> ProcessResult {
        let result = try run(executable, arguments, stdoutTo: stdoutTo, environment: environment)
        guard result.exitCode == 0 else {
            throw PeelError.toolFailed(name: executable.lastPathComponent, exitCode: result.exitCode,
                                       lastLine: result.lastErrorLine, details: result.stderr)
        }
        return result
    }
}
