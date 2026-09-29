import CoreGraphics

/// One reading of the global mouse/keyboard/drag state (all readable without special permission).
public struct DragSample: Equatable, Sendable {
    public var mouseDown: Bool
    public var shift: Bool
    /// `NSPasteboard(name: .drag).changeCount` — changes when any app starts a drag.
    public var dragChangeCount: Int
    public var hasFiles: Bool
    public var location: CGPoint

    public init(mouseDown: Bool, shift: Bool, dragChangeCount: Int, hasFiles: Bool, location: CGPoint) {
        self.mouseDown = mouseDown
        self.shift = shift
        self.dragChangeCount = dragChangeCount
        self.hasFiles = hasFiles
        self.location = location
    }
}

public enum DragEvent: Equatable, Sendable {
    case showWheel(at: CGPoint)
    case hideWheel
}

/// Decides when to show the action wheel: a file drag that started after the mouse went down, with
/// Shift held at some point. Once shown it stays until the mouse is released.
public struct DragDetector: Sendable {
    /// Drag-pasteboard change count last seen with the mouse button up. The drag pasteboard only
    /// changes while a button is down, so any later change means a drag started in this press —
    /// even a fast flick that began before the first "down" sample.
    private var baseline: Int?
    private var shown = false

    public init() {}

    public mutating func update(_ sample: DragSample) -> DragEvent? {
        guard sample.mouseDown else {
            baseline = sample.dragChangeCount
            if shown {
                shown = false
                return .hideWheel
            }
            return nil
        }
        let base = baseline ?? sample.dragChangeCount   // first ever sample mid-press: treat as no new drag
        if baseline == nil { baseline = base }
        if !shown && sample.shift && sample.hasFiles && sample.dragChangeCount != base {
            shown = true
            return .showWheel(at: sample.location)
        }
        return nil
    }
}
