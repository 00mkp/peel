import Testing
@testable import ConvertKit

@Suite struct PageRangeTests {
    @Test func parsesMixedSelection() throws {
        let range = try PageRange.parse("1-3, 5, 8-")
        #expect(range.items == [.span(1, 3), .single(5), .span(8, nil)])
        #expect(try range.pages(count: 10) == [1, 2, 3, 5, 8, 9, 10])
    }

    @Test func preservesOrderAndRepeats() throws {
        #expect(try PageRange.parse("3,1,2").pages(count: 3) == [3, 1, 2])
        #expect(try PageRange.parse("2,2").pages(count: 3) == [2, 2])
    }

    @Test func descendingSpanCountsDown() throws {
        #expect(try PageRange.parse("5-3").pages(count: 5) == [5, 4, 3])
    }

    @Test func groupsFollowItems() throws {
        #expect(try PageRange.parse("1-2,3").groups(count: 3) == [[1, 2], [3]])
    }

    @Test(arguments: ["", "0", "a", "1-2-3", "-3", "1,,2", "3-0", " , "])
    func rejectsMalformed(_ text: String) {
        #expect(throws: PeelError.invalidPageRange(text)) { try PageRange.parse(text) }
    }

    @Test func rejectsPagesPastTheEnd() throws {
        #expect(throws: PeelError.pageOutOfBounds(page: 4, count: 3)) { try PageRange.parse("4").pages(count: 3) }
        #expect(throws: PeelError.pageOutOfBounds(page: 9, count: 3)) { try PageRange.parse("2-9").pages(count: 3) }
        #expect(throws: PeelError.pageOutOfBounds(page: 8, count: 3)) { try PageRange.parse("8-").pages(count: 3) }
    }
}
