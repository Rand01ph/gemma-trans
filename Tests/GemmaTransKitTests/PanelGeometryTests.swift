import Testing
@testable import GemmaTransKit

@Suite struct PanelGeometryTests {
    @Test func contentWithinRangeKeepsVisualHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 300, screenVisibleHeight: 1000) == 300)
    }

    @Test func tinyContentClampsToMinimum() {
        #expect(PanelGeometry.targetHeight(contentHeight: 10, screenVisibleHeight: 900) == 132)
    }

    @Test func hugeContentClampsToMaxHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 1000) == 340)
    }

    @Test func smallScreenClampsToScreenFraction() {
        #expect(abs(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 500) - 250) < 0.001)
    }

    @Test func shadowGutterDoesNotChangeVisualHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 132, screenVisibleHeight: 900) == 132)
        #expect(PanelGeometry.windowWidth() == 540)
        #expect(PanelGeometry.windowHeight(forVisualHeight: 132) == 192)
        #expect(PanelGeometry.windowHeight(forVisualHeight: PanelGeometry.initialHeight) == 234)
    }

    @Test func resizeThresholdAvoidsStreamingJitter() {
        #expect(PanelGeometry.resizeThreshold == 24)
    }

    @Test func lockedOriginPreservesTopLeftAnchorWhenItFits() {
        let origin = PanelGeometry.lockedWindowOrigin(
            anchorX: 320,
            anchorTopY: 760,
            windowWidth: 540,
            windowHeight: 300,
            visibleMinX: 0,
            visibleMinY: 0,
            visibleMaxX: 1_440,
            visibleMaxY: 900
        )
        #expect(origin.x == 320)
        #expect(origin.y == 460)
    }

    @Test func lockedOriginClampsOnlyAtVisibleScreenEdges() {
        let origin = PanelGeometry.lockedWindowOrigin(
            anchorX: 1_200,
            anchorTopY: 260,
            windowWidth: 540,
            windowHeight: 300,
            visibleMinX: 0,
            visibleMinY: 0,
            visibleMaxX: 1_440,
            visibleMaxY: 900
        )
        #expect(origin.x == 890)
        #expect(origin.y == 10)
    }

    @Test func measuredResultSurfaceClampsToReadableRange() {
        #expect(PanelGeometry.resultSurfaceHeight(measuredContentHeight: 20) == 50)
        #expect(PanelGeometry.resultSurfaceHeight(measuredContentHeight: 108) == 108)
        #expect(PanelGeometry.resultSurfaceHeight(measuredContentHeight: 800) == 258)
    }

    @Test func measuredResultDeterminesFinalVisualHeight() {
        #expect(PanelGeometry.chromeHeight + PanelGeometry.streamingResultSurfaceHeight
            == PanelGeometry.initialHeight)
        #expect(PanelGeometry.preferredHeight(resultSurfaceHeight: 20) == 132)
        #expect(PanelGeometry.preferredHeight(
            resultSurfaceHeight: PanelGeometry.streamingResultSurfaceHeight
        ) == PanelGeometry.initialHeight)
        #expect(PanelGeometry.preferredHeight(resultSurfaceHeight: 180) == 262)
        #expect(PanelGeometry.preferredHeight(resultSurfaceHeight: 1_000) == 340)
    }

    @Test func overflowFadeOnlyAppearsWhileContentRemainsBelow() {
        #expect(PanelGeometry.hasContentBelow(contentHeight: 420, visibleMaxY: 258))
        #expect(!PanelGeometry.hasContentBelow(contentHeight: 420, visibleMaxY: 420))
        #expect(!PanelGeometry.hasContentBelow(contentHeight: 420, visibleMaxY: 419.5))
    }
}
