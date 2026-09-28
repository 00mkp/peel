import ArgumentParser
import ConvertKit
import Foundation

struct Formats: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show what converts to what — for everything, or for one file.")

    @Argument(help: "A file (or just a name such as x.heic) to list targets for.") var file: String?

    func run() throws {
        let locator = ToolLocator.standard
        guard let file else {
            printTable(locator: locator)
            return
        }
        guard let source = FileFormat(url: Paths.url(file)) else {
            Console.err("✗ unrecognized file type: \(file)")
            throw ExitCode(1)
        }
        if source.category == .archive {
            Console.out("archive: extract with 'peel x \(file)'")
            return
        }
        for target in Capabilities.targets(for: source) {
            guard let conversion = Capabilities.conversion(from: source, to: target) else { continue }
            let missing = Capabilities.missingTools(for: conversion, locator: locator)
            if missing.isEmpty {
                Console.out(target.rawValue)
            } else {
                let tools = missing.map(\.rawValue).joined(separator: ", ")
                let hints = missing.map(\.installHint).joined(separator: "; ")
                Console.out("\(target.rawValue)  (needs \(tools) → \(hints))")
            }
        }
    }

    private func printTable(locator: ToolLocator) {
        for category in FormatCategory.allCases {
            for source in FileFormat.allCases where source.category == category {
                let entries = Capabilities.targets(for: source).compactMap { target -> String? in
                    guard let conversion = Capabilities.conversion(from: source, to: target) else { return nil }
                    return target.rawValue + (Capabilities.missingTools(for: conversion, locator: locator).isEmpty ? "" : "*")
                }
                guard !entries.isEmpty else { continue }
                Console.out(source.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0) + " → " + entries.joined(separator: " "))
            }
        }
        Console.out("")
        Console.out("* needs an optional tool that isn't installed — run 'peel doctor'")
        Console.out("archives (zip, tar.gz, rar, 7z, …): extract with 'peel x', create with 'peel zip'")
    }
}
