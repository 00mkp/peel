import ArgumentParser
import ConvertKit
import Foundation

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check which optional tools are installed.")

    static func report(locator: ToolLocator) -> [String] {
        var lines = ["peel \(PeelRoot.configuration.version)", ""]
        let brew = "Homebrew".padding(toLength: 13, withPad: " ", startingAt: 0)
        lines.append(locator.homebrew.map { "✓ \(brew)\($0.path)" }
                     ?? "✗ \(brew)not found → \(ToolLocator.homebrewMissingNote)")
        for tool in Tool.allCases {
            let name = tool.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)
            if let url = locator.find(tool) {
                lines.append("✓ \(name)\(url.path)")
            } else {
                lines.append("✗ \(name)not found → \(tool.installHint)  (\(tool.enables))")
            }
        }
        lines.append("")
        lines.append("PDF tools, most image formats, subtitles, zip and tar need nothing extra.")
        return lines
    }

    func run() throws {
        Self.report(locator: .standard).forEach(Console.out)
    }
}
