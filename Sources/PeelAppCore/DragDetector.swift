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
    private var wasDown = false
    private var countAtMouseDown = 0
    private var shown = false

    public init() {}

    public mutating func update(_ sample: DragSample) -> DragEvent? {
        defer { wasDown = sample.mouseDown }
        if sample.mouseDown && !wasDown { countAtMouseDown = sample.dragChangeCount }
        guard sample.mouseDown else {
            if shown {
                shown = false
                return .hideWheel
            }
            return nil
        }
        if !shown && sample.shift && sample.hasFiles && sample.dragChangeCount != countAtMouseDown {
            shown = true
            return .showWheel(at: sample.location)
        }
        return nil
    }
}
