import Testing
@testable import GemmaTransKit

@Suite struct PanelGeometryTests {
    @Test func contentWithinRangeKeepsVisualHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 300, screenVisibleHeight: 1000) == 300)
    }

    @Test func tinyContentClampsToMinimum() {
        #expect(PanelGeometry.targetHeight(contentHeight: 10, screenVisibleHeight: 900) == 176)
    }

    @Test func hugeContentClampsToMaxHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 1000) == 340)
    }

    @Test func smallScreenClampsToScreenFraction() {
        #expect(abs(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 500) - 250) < 0.001)
    }

    @Test func shadowGutterDoesNotChangeVisualHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 176, screenVisibleHeight: 900) == 176)
        #expect(PanelGeometry.windowWidth() == 560)
        #expect(PanelGeometry.windowHeight(forVisualHeight: 176) == 236)
        #expect(PanelGeometry.windowHeight(forVisualHeight: PanelGeometry.initialHeight) == 280)
    }

    @Test func resizeThresholdAvoidsStreamingJitter() {
        #expect(PanelGeometry.resizeThreshold == 24)
    }

    @Test func measuredResultSurfaceClampsToReadableRange() {
        #expect(PanelGeometry.resultSurfaceHeight(measuredContentHeight: 20) == 76)
        #expect(PanelGeometry.resultSurfaceHeight(measuredContentHeight: 108) == 108)
        #expect(PanelGeometry.resultSurfaceHeight(measuredContentHeight: 800) == 240)
    }

    @Test func measuredResultDeterminesFinalVisualHeight() {
        #expect(PanelGeometry.chromeHeight + PanelGeometry.streamingResultSurfaceHeight
            == PanelGeometry.initialHeight)
        #expect(PanelGeometry.preferredHeight(resultSurfaceHeight: 20) == 176)
        #expect(PanelGeometry.preferredHeight(
            resultSurfaceHeight: PanelGeometry.streamingResultSurfaceHeight
        ) == PanelGeometry.initialHeight)
        #expect(PanelGeometry.preferredHeight(resultSurfaceHeight: 180) == 280)
        #expect(PanelGeometry.preferredHeight(resultSurfaceHeight: 1_000) == 340)
    }
}
