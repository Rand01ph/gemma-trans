import Testing
@testable import GemmaTransKit

@Suite struct PanelGeometryTests {
    @Test func contentWithinRangeGetsContentPlusChrome() {
        // 200 内容 + 96 chrome = 296，在 [140, 630] 内
        #expect(PanelGeometry.targetHeight(contentHeight: 200, screenVisibleHeight: 900) == 296)
    }

    @Test func tinyContentClampsToMinimum() {
        #expect(PanelGeometry.targetHeight(contentHeight: 10, screenVisibleHeight: 900) == 140)
    }

    @Test func hugeContentClampsTo70PercentOfScreen() {
        #expect(PanelGeometry.targetHeight(contentHeight: 2000, screenVisibleHeight: 1000) == 700)
    }
}
