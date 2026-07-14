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
        s.appearance = .dark
        s.save(suiteName: suite)

        let loaded = AppSettings.load(suiteName: suite)
        #expect(loaded.targetDefault == "ja")
        #expect(loaded.manualMaxTokens == 512)
        #expect(loaded.useCNSource == true)
        #expect(loaded.appearance == .dark)
    }

    /// 国内源开关默认关闭（HF 直连可用的用户不受影响）
    @Test func useCNSourceDefaultsToFalse() {
        #expect(AppSettings().useCNSource == false)
    }

    /// 兼容回归：无参调用仍走 macOS 既有 suite
    @Test func defaultSuiteNameUnchanged() {
        #expect(AppSettings.suiteName == "com.gemmatrans.app")
    }

    /// 新用户默认不选择模型，启动时不得因此触发下载。
    @Test func selectedModelIDDefaultsToNil() {
        #expect(AppSettings().selectedModelID == nil)
    }

    /// selectedModelID 随 UserDefaults 持久化往返
    @Test func test_selectedModelID_roundTripsThroughDefaults() {
        let suite = "test.selectedModel.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var s = AppSettings()
        s.selectedModelID = "hymt2-8bit"
        s.save(suiteName: suite)
        #expect(AppSettings.load(suiteName: suite).selectedModelID == "hymt2-8bit")
    }

    @Test func legacyAutoAndUnknownModelIDsMigrateToNoSelection() {
        let suite = "test.legacyModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("auto", forKey: "selectedModelID")
        #expect(AppSettings.load(suiteName: suite).selectedModelID == nil)

        defaults.set("unknown-model", forKey: "selectedModelID")
        #expect(AppSettings.load(suiteName: suite).selectedModelID == nil)
    }

    @Test func appearanceDefaultsToSystem() {
        #expect(AppSettings().appearance == .system)
    }
}
