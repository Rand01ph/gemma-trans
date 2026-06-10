import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct SystemMemoryTests {
    @Test func physicalMatchesProcessInfo() {
        #expect(SystemMemory.physical() == ProcessInfo.processInfo.physicalMemory)
    }

    @Test func availableIsPositiveAndSane() throws {
        let available = try #require(SystemMemory.available())
        #expect(available > 0)
        #expect(available <= SystemMemory.physical())
    }
}
