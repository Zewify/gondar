import Foundation
import Testing

@testable import GondarCore

// AppKit coordinates: y grows upwards, so a window's top edge is maxY.
private let visible = WindowFit.Rect(x: 0, y: 0, width: 1920, height: 1055)

@Test func growsDownwardKeepingTheTopEdge() {
    let frame = WindowFit.Rect(x: 1120, y: 600, width: 320, height: 300)
    let fitted = WindowFit.frame(fitting: frame, content: 400, viewport: 282, minimumHeight: 140, within: visible)
    #expect(fitted == WindowFit.Rect(x: 1120, y: 482, width: 320, height: 418))
}

@Test func shrinksToContentButNotBelowTheMinimum() {
    let frame = WindowFit.Rect(x: 100, y: 600, width: 320, height: 300)
    #expect(WindowFit.frame(fitting: frame, content: 200, viewport: 282, minimumHeight: 140, within: visible).height == 218)
    #expect(WindowFit.frame(fitting: frame, content: 10, viewport: 282, minimumHeight: 140, within: visible).height == 140)
}

@Test func roundsPartialPointsUp() {
    let frame = WindowFit.Rect(x: 100, y: 600, width: 320, height: 300)
    #expect(WindowFit.frame(fitting: frame, content: 300.4, viewport: 282, minimumHeight: 140, within: visible).height == 319)
}

@Test func capsToTheVisibleFrameAndStaysInsideIt() {
    let frame = WindowFit.Rect(x: 1120, y: 800, width: 320, height: 300)
    let fitted = WindowFit.frame(fitting: frame, content: 3000, viewport: 282, minimumHeight: 140, within: visible)
    #expect(fitted == WindowFit.Rect(x: 1120, y: 0, width: 320, height: 1055))
}

@Test func movedBackInsideWhenGrowingWouldPassTheBottom() {
    let frame = WindowFit.Rect(x: 1120, y: 50, width: 320, height: 300)
    let fitted = WindowFit.frame(fitting: frame, content: 500, viewport: 282, minimumHeight: 140, within: visible)
    #expect(fitted == WindowFit.Rect(x: 1120, y: 0, width: 320, height: 518))
}

@Test func worksOnADisplayAboveTheMainOne() {
    let upper = WindowFit.Rect(x: 0, y: 1080, width: 1920, height: 1055)
    let frame = WindowFit.Rect(x: 1120, y: 1900, width: 320, height: 300)
    // Top edge 2200 is above the visible top (2135): the window comes down inside it.
    let fitted = WindowFit.frame(fitting: frame, content: 400, viewport: 282, minimumHeight: 140, within: upper)
    #expect(fitted == WindowFit.Rect(x: 1120, y: 2135 - 418, width: 320, height: 418))
}
