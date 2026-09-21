import XCTest
import AppKit

@MainActor
final class UIContractTests: XCTestCase {
    private func launch(_ scene: String, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "GEMMATRANS_SCREENSHOT_SCENE": scene,
            "GEMMATRANS_SCREENSHOT_APPEARANCE": appearance,
            "GEMMATRANS_TEST_SUITE": "com.gemmatrans.ui-test.\(UUID().uuidString)"
        ]
        app.launch()
        return app
    }

    func testCompletedPanelRateCopyPinAndClose() {
        let app = launch("panel-completed")
        defer { app.terminate() }
        let rate = app.staticTexts["panel.rate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 10))
        XCTAssertEqual(rate.value as? String ?? rate.label, "72.4 tok/s")
        XCTAssertGreaterThanOrEqual(rate.frame.minX, app.buttons["panel.speak"].frame.maxX)
        XCTAssertEqual(rate.frame.midY, app.buttons["panel.copy"].frame.midY, accuracy: 1)
        XCTAssertGreaterThan(rate.frame.minY, app.staticTexts["panel.direction"].frame.maxY)
        let clipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        defer {
            NSPasteboard.general.clearContents()
            let items = clipboard.map { data in
                let item = NSPasteboardItem()
                for (type, bytes) in data { item.setData(bytes, forType: type) }
                return item
            }
            NSPasteboard.general.writeObjects(items)
        }
        app.buttons["panel.copy"].click()
        XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("Great tools") == true)
        app.buttons["panel.pin"].click()
        XCTAssertTrue(app.buttons["panel.pin"].exists)
        app.buttons["panel.close"].click()
        XCTAssertFalse(rate.exists)
    }

    func testRunningPanelStopsAndDoesNotShowOldRate() {
        let app = launch("panel-running")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["panel.stop"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["panel.rate"].exists)
        app.buttons["panel.stop"].click()
        XCTAssertTrue(app.buttons["panel.copy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["panel.stop"].exists)
    }

    func testMainClearAndSettingsNavigation() {
        let app = launch("main-completed")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["main.clear"].waitForExistence(timeout: 10))
        app.buttons["main.clear"].click()
        XCTAssertFalse(app.buttons["main.translate"].isEnabled)
        app.buttons["设置"].click()
        XCTAssertTrue(app.windows["通用"].waitForExistence(timeout: 5))
    }

    func testNativeMenu() throws {
        for appearance in ["light", "dark"] {
            let app = launch("menu", appearance: appearance)
            defer { app.terminate() }
            let item = app.descendants(matching: .statusItem)["GemmaTrans"]
            XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
            item.click()
            let show = app.menuItems["显示窗口"]
            XCTAssertTrue(show.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.menuItems["设置…"].exists)
            XCTAssertTrue(app.menuItems["退出"].exists)
            let menu = try XCTUnwrap(app.menus.allElementsBoundByIndex.first { !$0.frame.isEmpty })
            let screenshot = menu.screenshot()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: screenshot.pngRepresentation))
            let elements: [[String: Any]] = [("menu.apiStatus", "API：已关闭"), ("menu.show", "显示窗口"), ("menu.api", "本地 API"), ("menu.settings", "设置…"), ("menu.quit", "退出")].map { id, title in
                let element = app.menuItems[title]
                return ["id": id, "text": title, "enabled": element.isEnabled,
                    "frame": [element.frame.minX - menu.frame.minX, element.frame.minY - menu.frame.minY,
                              element.frame.width, element.frame.height]]
            }
            let metadata: [String: Any] = ["scene": "menu", "appearance": appearance,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "font": NSFont.systemFont(ofSize: 13).fontName,
                "scale": Double(bitmap.pixelsWide) / menu.frame.width,
                "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh, "elements": elements]
            let metadataAttachment = XCTAttachment(data: try JSONSerialization.data(
                withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            metadataAttachment.name = "menu-\(appearance).json"
            metadataAttachment.lifetime = .keepAlways
            add(metadataAttachment)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "menu-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            show.click()
            XCTAssertTrue(app.windows["GemmaTrans"].exists)
        }
    }
}
