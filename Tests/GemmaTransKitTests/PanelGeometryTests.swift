import Testing
@testable import GemmaTransKit

@Suite struct PanelGeometryTests {
    @Test func contentWithinRangeGetsContentPlusChrome() {
        // 200 内容 + 76 chrome = 276，在 [140, 630] 内
        #expect(PanelGeometry.targetHeight(contentHeight: 200, screenVisibleHeight: 900) == 276)
    }

    @Test func tinyContentClampsToMinimum() {
        #expect(PanelGeometry.targetHeight(contentHeight: 10, screenVisibleHeight: 900) == 140)
    }

    @Test func hugeContentClampsTo70PercentOfScreen() {
        #expect(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 1000) == 700)
    }

    @Test func frameInsideVisibleAreaIsUnchanged() {
        let frame = PanelGeometry.Frame(x: 120, y: 160, width: 420, height: 260)
        let visible = PanelGeometry.Frame(x: 0, y: 40, width: 900, height: 700)

        #expect(PanelGeometry.clampedFrame(frame, visibleFrame: visible) == frame)
    }

    @Test func frameOutsideVisibleAreaIsClampedBackInside() {
        let frame = PanelGeometry.Frame(x: 760, y: 10, width: 420, height: 260)
        let visible = PanelGeometry.Frame(x: 0, y: 40, width: 900, height: 700)

        #expect(
            PanelGeometry.clampedFrame(frame, visibleFrame: visible)
                == PanelGeometry.Frame(x: 480, y: 40, width: 420, height: 260)
        )
    }

    @Test func resizingKeepsTopEdgeWhenRoomAllows() {
        let frame = PanelGeometry.Frame(x: 120, y: 260, width: 420, height: 180)
        let visible = PanelGeometry.Frame(x: 0, y: 40, width: 900, height: 700)

        #expect(
            PanelGeometry.resizedFrameKeepingTop(frame, targetHeight: 260, visibleFrame: visible)
                == PanelGeometry.Frame(x: 120, y: 180, width: 420, height: 260)
        )
    }

    @Test func resizingClampsBottomToVisibleArea() {
        let frame = PanelGeometry.Frame(x: 120, y: 60, width: 420, height: 180)
        let visible = PanelGeometry.Frame(x: 0, y: 40, width: 900, height: 700)

        #expect(
            PanelGeometry.resizedFrameKeepingTop(frame, targetHeight: 260, visibleFrame: visible)
                == PanelGeometry.Frame(x: 120, y: 40, width: 420, height: 260)
        )
    }
}
