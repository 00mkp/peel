import CoreGraphics
import Testing
@testable import PeelAppCore

@Suite struct DragDetectorTests {
    private func s(_ down: Bool, shift: Bool = false, count: Int = 1, files: Bool = true,
                   at point: CGPoint = CGPoint(x: 10, y: 20)) -> DragSample {
        DragSample(mouseDown: down, shift: shift, dragChangeCount: count, hasFiles: files, location: point)
    }

    @Test func shiftDragOfFilesShowsOnceThenHidesOnMouseUp() {
        var d = DragDetector()
        #expect(d.update(s(false, count: 1)) == nil)
        #expect(d.update(s(true, count: 1)) == nil)                          // mouse down, no drag yet
        #expect(d.update(s(true, shift: true, count: 1)) == nil)             // shift but no drag started
        #expect(d.update(s(true, shift: true, count: 2)) == .showWheel(at: CGPoint(x: 10, y: 20)))
        #expect(d.update(s(true, shift: true, count: 2)) == nil)             // only once
        #expect(d.update(s(true, shift: false, count: 2)) == nil)            // releasing Shift keeps it
        #expect(d.update(s(false, count: 2)) == .hideWheel)
        #expect(d.update(s(false, count: 2)) == nil)
    }

    @Test func dragWithoutShiftNeverShows() {
        var d = DragDetector()
        _ = d.update(s(true, count: 5))
        #expect(d.update(s(true, count: 6)) == nil)
        #expect(d.update(s(false, count: 6)) == nil)
    }

    @Test func shiftPressedLateInTheDragStillShows() {
        var d = DragDetector()
        _ = d.update(s(true, count: 5))
        #expect(d.update(s(true, count: 6)) == nil)
        #expect(d.update(s(true, shift: true, count: 6, at: CGPoint(x: 1, y: 2))) == .showWheel(at: CGPoint(x: 1, y: 2)))
    }

    @Test func nonFileDragsAreIgnored() {
        var d = DragDetector()
        _ = d.update(s(true, count: 5))
        #expect(d.update(s(true, shift: true, count: 6, files: false)) == nil)
    }

    @Test func staleDragFromBeforeMouseDownIsIgnored() {
        var d = DragDetector()
        _ = d.update(s(false, count: 9))
        #expect(d.update(s(true, shift: true, count: 9)) == nil)             // pasteboard unchanged since mouse-down
    }

    @Test func eachDragShowsAgain() {
        var d = DragDetector()
        _ = d.update(s(true, count: 1))
        #expect(d.update(s(true, shift: true, count: 2)) != nil)
        #expect(d.update(s(false, count: 2)) == .hideWheel)
        _ = d.update(s(true, count: 2))
        #expect(d.update(s(true, shift: true, count: 3)) != nil)
    }
}
