import Foundation

/// Where the floating window goes when it is fitted to its rows once: the height that shows every row,
/// at least the minimum and at most the visible frame, keeping the top edge and staying inside the visible frame.
public enum WindowFit {
    /// A rectangle in AppKit's screen coordinates, where y grows upwards; Core stays free of CoreGraphics.
    public struct Rect: Sendable, Equatable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    public static func frame(fitting frame: Rect, content: Double, viewport: Double, minimumHeight: Double, within visible: Rect) -> Rect {
        let height = min(max(frame.height + (content - viewport).rounded(.up), minimumHeight), visible.height)
        let top = frame.y + frame.height
        let y = min(max(top - height, visible.y), visible.y + visible.height - height)
        let x = min(max(frame.x, visible.x), max(visible.x, visible.x + visible.width - frame.width))
        return Rect(x: x, y: y, width: frame.width, height: height)
    }
}
