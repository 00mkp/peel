import ArgumentParser
import Foundation

public struct Peel: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "peel",
        abstract: "Convert and edit images, PDFs, audio/video, subtitles and archives — all locally.",
        version: "0.1.0",
        subcommands: [Convert.self, PDFCommand.self, MediaCommand.self, Formats.self])

    public init() {}

    /// Parses and runs a command, returning the process exit code:
    /// 0 success, 1 a file failed, 2 usage error.
    public static func execute(_ arguments: [String]?) -> Int32 {
        do {
            var command = try parseAsRoot(arguments)
            try command.run()
            return 0
        } catch {
            let code = exitCode(for: error)
            let message = fullMessage(for: error)
            if code == .success {
                if !message.isEmpty { Console.out(message) }
                return 0
            }
            if code == .validationFailure {
                Console.err(message)
                return 2
            }
            if !message.isEmpty { Console.err(message) }
            return code.rawValue
        }
    }

    public static func runMain() -> Never {
        Foundation.exit(execute(nil))
    }
}
