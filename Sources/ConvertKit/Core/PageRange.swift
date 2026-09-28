import Foundation

/// A page selection such as "1-3,5,8-" (1-based, inclusive; "8-" = page 8 to the end;
/// "5-3" counts down). Order and repeats are preserved so one type serves split, extract and reorder.
public struct PageRange: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        case single(Int)
        case span(Int, Int?)
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public static func parse(_ text: String) throws -> PageRange {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.contains(where: \.isEmpty) else { throw PeelError.invalidPageRange(text) }
        var items: [Item] = []
        for part in parts {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            switch bounds.count {
            case 1:
                guard let page = Int(bounds[0]), page >= 1 else { throw PeelError.invalidPageRange(text) }
                items.append(.single(page))
            case 2:
                guard let start = Int(bounds[0]), start >= 1 else { throw PeelError.invalidPageRange(text) }
                if bounds[1].isEmpty {
                    items.append(.span(start, nil))
                } else {
                    guard let end = Int(bounds[1]), end >= 1 else { throw PeelError.invalidPageRange(text) }
                    items.append(.span(start, end))
                }
            default:
                throw PeelError.invalidPageRange(text)
            }
        }
        return PageRange(items: items)
    }

    /// One page list per item, validated against a document of `count` pages.
    public func groups(count: Int) throws -> [[Int]] {
        try items.map { item in
            switch item {
            case let .single(page):
                guard page <= count else { throw PeelError.pageOutOfBounds(page: page, count: count) }
                return [page]
            case let .span(start, end):
                let last = end ?? count
                guard start <= count else { throw PeelError.pageOutOfBounds(page: start, count: count) }
                guard last <= count else { throw PeelError.pageOutOfBounds(page: last, count: count) }
                return start <= last ? Array(start...last) : Array((last...start).reversed())
            }
        }
    }

    /// Every selected page, in order, repeats kept.
    public func pages(count: Int) throws -> [Int] {
        try groups(count: count).flatMap { $0 }
    }
}
