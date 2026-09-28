import Foundation

/// Where CLI output goes. Task-local so tests can capture output while running in parallel.
public struct Console: Sendable {
    public var out: @Sendable (String) -> Void
    public var err: @Sendable (String) -> Void

    public init(out: @escaping @Sendable (String) -> Void, err: @escaping @Sendable (String) -> Void) {
        self.out = out
        self.err = err
    }

    @TaskLocal public static var current = Console(
        out: { print($0) },
        err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })

    public static func out(_ line: String) { current.out(line) }
    public static func err(_ line: String) { current.err(line) }
}
