import AppKit
import XCTest

@MainActor
final class SystemServiceTests: XCTestCase {
    /// Opt-in: requires an already installed MLX model; never downloads a model.
    func testWholeArticleThroughMacOSService() throws {
        guard ProcessInfo.processInfo.environment["GT_SERVICE_TEST"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_GT_SERVICE_TEST=1 on a Mac with hymt2-4bit installed")
        }
        let suite = "com.gemmatrans.ui-test.service.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("hymt2-4bit", forKey: "selectedModelID")
        defaults.set(false, forKey: "apiEnabled")
        defaults.set(38765, forKey: "port")
        defaults.synchronize()
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = XCUIApplication()
        app.launchEnvironment = ["GEMMATRANS_TEST_SUITE": suite]
        app.launchArguments = ["-selectedModelID", "hymt2-4bit", "-apiEnabled", "NO", "-port", "38765"]
        app.launch()
        defer { app.terminate() }
        guard app.descendants(matching: .any)["引擎状态：就绪"].waitForExistence(timeout: 30) else {
            XCTFail(app.debugDescription); return
        }
        let article = (1...12).map { number in
            "GT\(String(format: "%03d", number)): The library opens at nine in the morning. Visitors can read books, borrow a computer, and ask for help at the front desk. Please keep this reference code unchanged when translating. Every Saturday, the library offers a free workshop for families who want to learn about local history."
        }.joined(separator: "\n\n")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(article, forType: .string)
        XCTAssertTrue(NSPerformService(ProcessInfo.processInfo.environment["GT_SERVICE_NAME"] ?? "Translate with GemmaTrans UITest", board), "Service registration must target this signed test build")
        XCTAssertTrue(app.staticTexts["panel.rate"].waitForExistence(timeout: 120), app.debugDescription)
        let originalClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(originalClipboard.map { data in
                let item = NSPasteboardItem()
                for (type, bytes) in data { item.setData(bytes, forType: type) }
                return item
            })
        }
        app.buttons["panel.copy"].click()
        let translation = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        for n in 1...12 { XCTAssertTrue(translation.contains(String(format: "GT%03d", n))) }
        let textAttachment = XCTAttachment(string: translation)
        textAttachment.name = "service-validation.txt"
        textAttachment.lifetime = .keepAlways
        add(textAttachment)
        let screenshot = XCTAttachment(screenshot: app.windows.element(boundBy: 0).screenshot())
        screenshot.name = "macOS-service-long-article"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
