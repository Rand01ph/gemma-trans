import Testing
@testable import GemmaTransKit

@Suite struct PanelGeometryTests {
    @Test func contentWithinRangeKeepsVisualHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 420, screenVisibleHeight: 1000) == 420)
    }

    @Test func tinyContentClampsToMinimum() {
        #expect(PanelGeometry.targetHeight(contentHeight: 10, screenVisibleHeight: 900) == 330)
    }

    @Test func hugeContentClampsToMaxHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 1000) == 520)
    }

    @Test func smallScreenClampsToScreenFraction() {
        #expect(abs(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 700) - 392) < 0.001)
    }

    @Test func shadowGutterDoesNotChangeVisualHeight() {
        #expect(PanelGeometry.targetHeight(contentHeight: 330, screenVisibleHeight: 900) == 330)
        #expect(PanelGeometry.windowWidth() == 656)
        #expect(PanelGeometry.windowHeight(forVisualHeight: 330) == 366)
    }
}
