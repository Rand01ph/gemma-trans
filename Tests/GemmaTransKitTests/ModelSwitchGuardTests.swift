import Testing
@testable import GemmaTransKit

@Suite struct ModelSwitchGuardTests {
    @Test func idle_allowsSwitch() {
        #expect(ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: false, apiRunning: false) == nil)
    }

    @Test func generating_blocks() {
        #expect(ModelSwitchGuard.blockReason(
            isGenerating: true, isLoading: false, apiRunning: false) == .generating)
    }

    @Test func loading_blocks() {
        #expect(ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: true, apiRunning: false) == .loading)
    }

    @Test func apiRunning_blocks() {
        #expect(ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: false, apiRunning: true) == .apiRunning)
    }

    @Test func priority_generatingFirst() {
        // 优先级：生成 > 加载 > API（稳定的提示文案）
        #expect(ModelSwitchGuard.blockReason(
            isGenerating: true, isLoading: true, apiRunning: true) == .generating)
    }

    @Test func message_generating() {
        #expect(SwitchBlock.generating.message == "正在翻译，请稍候再切换模型")
    }

    @Test func message_loading() {
        #expect(SwitchBlock.loading.message == "模型加载中，请稍候再切换")
    }

    @Test func message_apiRunning() {
        #expect(SwitchBlock.apiRunning.message == "本地 API 运行中，请先在设置里关闭 API 再切换模型")
    }
}
