import Testing
@testable import GemmaTransKit

@Suite struct AppChannelTests {
    @Test func channelsDoNotShareMutableStateOrPorts() {
        #expect(Set(AppChannel.allCases.map(\.settingsSuite)).count == 4)
        #expect(Set(AppChannel.allCases.map(\.displayName)).count == 4)
        #expect(Set(AppChannel.allCases.map(\.defaultPort)).count == 4)
        #expect(AppChannel.production.settingsSuite == "com.gemmatrans.app")
        #expect(AppChannel.production.defaultPort == 8765)
    }
}
