import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct AppSettingsTests {
    /// iOS 上主 app 与扩展经 App Group suite 共享设置；suite 必须可注入
    @Test func roundTripsThroughCustomSuite() {
        let suite = "test.gemmatrans.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var s = AppSettings()
        s.targetDefault = "ja"
        s.manualMaxTokens = 512
        s.useCNSource = true
        s.save(suiteName: suite)

        let loaded = AppSettings.load(suiteName: suite)
        #expect(loaded.targetDefault == "ja")
        #expect(loaded.manualMaxTokens == 512)
        #expect(loaded.useCNSource == true)
    }

    /// 国内源开关默认关闭（HF 直连可用的用户不受影响）
    @Test func useCNSourceDefaultsToFalse() {
        #expect(AppSettings().useCNSource == false)
    }

    /// 兼容回归：无参调用仍走 macOS 既有 suite
    @Test func defaultSuiteNameUnchanged() {
        #expect(AppSettings.suiteName == "com.gemmatrans.app")
    }
}
