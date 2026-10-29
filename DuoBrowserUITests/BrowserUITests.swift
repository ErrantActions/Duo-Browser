import XCTest
import UIKit

final class BrowserUITests: XCTestCase {
    @MainActor
    func testDemoPanelEventsAndTabLifecycle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        let demo = app.buttons["Explore DuoKit Demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()
        let install = app.webViews.buttons["Install Duo Panel"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        install.tap()
        let deny = app.buttons["Deny for This Site"]
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        captureScreenshot(app, name: "Duo Controls Permission Denied")
        XCTAssertTrue(deny.waitForNonExistence(timeout: 10))
        openMenu(in: app)
        let permissions = app.buttons["Duo Site Permissions"]
        scrollTo(permissions, in: app)
        permissions.tap()
        app.buttons["Ask Again Next Time"].tap()
        app.buttons["Done"].tap()
        install.tap()
        let allow = app.buttons["Allow for This Site"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()
        revealDuoControlsIfNeeded(in: app)
        let reserve = app.buttons["duo.control.reserve"]
        XCTAssertTrue(reserve.waitForExistence(timeout: 10))
        captureScreenshot(app, name: "Native Duo Panel")
        reserve.tap()
        dismissCompactDuoControlsIfNeeded(in: app)
        let eventLog = app.webViews.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "duo.controlActivated")
        ).firstMatch
        XCTAssertTrue(eventLog.waitForExistence(timeout: 10))
        let clear = app.webViews.buttons["Clear Duo Panel"]
        clear.tap()
        openMenu(in: app)
        app.buttons["New Tab"].tap()
        let tabs = app.buttons["Tabs, 2 open"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.tap()
        let start = app.buttons["Close tab"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Tabs, 1 open"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testDuoNativeToolbarKeepsWebsiteVisibleAndDeliversNavigation() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        XCTAssertTrue(app.buttons["browser.address.open"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "browser.bottom.chrome").firstMatch.exists)
        openMenu(in: app)
        app.buttons["New Private Tab"].tap()
        let demo = app.buttons["Explore DuoKit Demo"]
        let start = app.scrollViews["browser.start-page"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            if demo.exists && demo.isHittable { break }
            start.swipeUp()
        }
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        let install = app.webViews.buttons["Install Duo Panel"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        install.tap()
        let allow = app.buttons["Allow for This Site"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()

        let next = app.buttons["duo.control.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let webpage = app.webViews.firstMatch
        print("Duo native viewport: windowWidth=\(app.frame.width), windowHeight=\(app.frame.height), webX=\(webpage.frame.minX), webY=\(webpage.frame.minY), webWidth=\(webpage.frame.width), webHeight=\(webpage.frame.height), actionX=\(next.frame.minX), actionWidth=\(next.frame.width)")
        XCTAssertGreaterThan(webpage.frame.width, app.frame.width * 0.6)
        XCTAssertGreaterThan(webpage.frame.height, app.frame.height * 0.85)
        XCTAssertGreaterThanOrEqual(next.frame.minX, webpage.frame.maxX - 2)
        XCTAssertLessThan(next.frame.width, app.frame.width * 0.25)
        XCTAssertTrue(app.buttons["Browser menu"].exists)
        XCTAssertTrue(app.buttons["duo.browser.back"].exists)
        XCTAssertTrue(app.buttons["duo.browser.refresh"].exists)
        XCTAssertFalse(app.buttons["duo.controls.open"].exists)
        let addressButton = app.buttons["browser.address.open"]
        XCTAssertTrue(addressButton.exists)
        XCTAssertEqual(addressButton.label, "URL")
        XCTAssertLessThanOrEqual(addressButton.frame.width, 64)
        XCTAssertFalse(app.textFields["Address and search"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "browser.bottom.chrome").firstMatch.exists)
        for button in [addressButton, app.buttons["duo.browser.back"], app.buttons["duo.browser.refresh"], app.buttons["browser.tabs"], app.buttons["Browser menu"]] {
            XCTAssertTrue(button.exists)
            XCTAssertFalse(webpage.frame.intersects(button.frame))
        }
        for identifier in ["browser.address.open", "duo.browser.back", "duo.browser.refresh", "browser.tabs"] {
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
        }
        XCTAssertEqual(app.buttons.matching(identifier: "Browser menu").count, 1)
        captureScreenshot(app, name: "Full Safe Viewport With Native Duo Edge Controls")

        let background = app.webViews.buttons["Toggle Page Background"]
        for (name, rgb) in [("Teal", [224, 245, 236]), ("Navy", [20, 42, 61])] {
            for _ in 0..<4 {
                if background.exists && background.isHittable { break }
                webpage.swipeUp()
            }
            XCTAssertTrue(background.isHittable)
            background.tap()
            XCTAssertTrue(app.webViews.staticTexts["Page background: \(name)"].waitForExistence(timeout: 10))
            let image = try XCTUnwrap(app.screenshot().image.cgImage)
            for x in [webpage.frame.minX + 2, webpage.frame.maxX + 2, app.frame.maxX - 2] {
                let actual = try pixel(at: CGPoint(x: x, y: webpage.frame.midY), in: image, window: app.frame)
                print("Duo background: variant=\(name), sampleX=\(x), red=\(actual[0]), green=\(actual[1]), blue=\(actual[2])")
                for channel in 0..<3 { XCTAssertEqual(Double(actual[channel]), Double(rgb[channel]), accuracy: 8) }
            }
        }

        next.tap()
        XCTAssertTrue(app.webViews.staticTexts["Record 2 of 3"].waitForExistence(timeout: 10))
        addressButton.tap()
        let bubble = app.textFields["browser.address.bubble.field"]
        let bubbleExists = bubble.waitForExistence(timeout: 10)
        print("Duo address expansion: bubbleField=\(bubbleExists), addressFields=\(app.textFields.matching(identifier: "Address and search").count), keyboards=\(app.keyboards.count), fullEditor=\(app.navigationBars["Address and Search"].exists), bottomChrome=\(app.descendants(matching: .any).matching(identifier: "browser.bottom.chrome").firstMatch.exists)")
        XCTAssertTrue(bubbleExists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Address and Search"].exists)
        XCTAssertEqual(app.textFields.matching(identifier: "Address and search").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "browser.address.open").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "Clear address").count, 1)
        XCTAssertTrue(addressButton.isEnabled)
        XCTAssertTrue(addressButton.isHittable)
        XCTAssertFalse(next.exists && next.isEnabled)
        print("Duo address bubble: addressX=\(addressButton.frame.minX), addressY=\(addressButton.frame.minY), addressHeight=\(addressButton.frame.height), fieldX=\(bubble.frame.minX), fieldY=\(bubble.frame.minY), fieldWidth=\(bubble.frame.width), fieldHeight=\(bubble.frame.height)")
        XCTAssertFalse(bubble.frame.intersects(addressButton.frame))
        XCTAssertLessThan(abs(bubble.frame.midY - addressButton.frame.midY), 44)
        let connectedImage = try XCTUnwrap(app.screenshot().image.cgImage)
        let connected = try pixel(
            at: CGPoint(x: webpage.frame.maxX + 1, y: bubble.frame.midY),
            in: connectedImage, window: app.frame
        )
        XCTAssertGreaterThan(abs(Int(connected[0]) - 20) + abs(Int(connected[1]) - 42) + abs(Int(connected[2]) - 61), 60)
        print("Duo connected bubble: red=\(connected[0]), green=\(connected[1]), blue=\(connected[2])")
        app.buttons["Clear address"].tap()
        bubble.typeText("javascript:alert(1)")
        app.buttons["browser.address.bubble.go"].tap()
        XCTAssertTrue(app.staticTexts["browser.address.validation"].waitForExistence(timeout: 5))
        XCTAssertTrue(bubble.exists)
        app.buttons["Clear address"].tap()
        bubble.typeText("https://example.com/draft")
        addressButton.tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Address and Search"].exists)
        XCTAssertFalse(app.textFields["browser.address.editor"].exists)
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(app.webViews.staticTexts["Record 2 of 3"].exists)
        addressButton.tap()
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        XCTAssertTrue((bubble.value as? String)?.contains("index.html") == true)
        webpage.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["Record 2 of 3"].exists)
        XCTAssertTrue(app.buttons["duo.control.previous"].isEnabled)
        let previous = app.buttons["duo.control.previous"]
        previous.tap()
        XCTAssertTrue(app.webViews.staticTexts["Record 1 of 3"].waitForExistence(timeout: 10))

        app.buttons["duo.browser.refresh"].tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 10))
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Browser menu"].exists)
        install.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        app.webViews.buttons["Clear Duo Panel"].tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 10))
        XCTAssertTrue(webpage.exists)
        navigate("https://example.com", in: app)
        assertLoadedHTTPSPage(in: app, host: "example.com")
        XCTAssertFalse(app.textFields["Address and search"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "browser.bottom.chrome").firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "browser.address.open").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "duo.browser.refresh").count, 1)
    }

    @MainActor
    private func revealDuoControlsIfNeeded(in app: XCUIApplication) {
        let open = app.buttons["duo.controls.open"]
        if open.waitForExistence(timeout: 2) {
            open.tap()
            XCTAssertTrue(app.navigationBars["Website Controls"].waitForExistence(timeout: 10))
        } else if app.buttons["duo.controls.all"].exists {
            app.buttons["duo.controls.all"].tap()
            XCTAssertTrue(app.navigationBars["Website Controls"].waitForExistence(timeout: 10))
        }
    }

    @MainActor
    private func dismissCompactDuoControlsIfNeeded(in app: XCUIApplication) {
        let title = app.navigationBars["Website Controls"]
        if title.exists { title.buttons["Done"].tap() }
    }

    @MainActor
    func testFavoriteCanBeSavedAndOpenedFromTheStartPage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        openMenu(in: app)
        app.buttons["New Tab"].tap()
        navigate("https://example.com", in: app)
        assertLoadedHTTPSPage(in: app, host: "example.com")

        openMenu(in: app)
        let addBookmark = app.buttons["Add Bookmark"]
        scrollTo(addBookmark, in: app)
        addBookmark.tap()
        let title = app.textFields["Bookmark title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(" UI-\(UUID().uuidString.prefix(6))")
        let savedTitle = try XCTUnwrap(title.value as? String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let favoriteSwitch = app.switches["bookmark.favorite"]
        if favoriteSwitch.value as? String != "1" { favoriteSwitch.tap() }
        XCTAssertEqual(favoriteSwitch.value as? String, "1")
        app.buttons["Save"].tap()

        openMenu(in: app)
        app.buttons["Start Page"].tap()
        let favorite = app.buttons["Open favorite \(savedTitle)"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        captureScreenshot(app, name: "Start Page Favorites")
        favorite.tap()
        assertLoadedHTTPSPage(in: app, host: "example.com")
    }

    @MainActor
    func testHTTPSAddressAndBackForwardNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        openMenu(in: app)
        app.buttons["New Tab"].tap()

        navigate("example.com", in: app)
        assertLoadedHTTPSPage(in: app, host: "example.com")
        captureScreenshot(app, name: "Ordinary HTTPS Browsing")

        navigate("https://example.com/?duo=second", in: app)
        assertLoadedHTTPSPage(in: app, host: "example.com")
        let back = app.buttons["Back"]
        waitUntilEnabled(back)
        back.tap()
        let forward = app.buttons["Forward"]
        if app.buttons["browser.address.open"].exists { openMenu(in: app) }
        waitUntilEnabled(forward)
        forward.tap()
        assertLoadedHTTPSPage(in: app, host: "example.com")
    }

    @MainActor
    func testTabGridSwitchesRegularAndPrivateSessions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        let overview = app.buttons["browser.tabs"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        waitUntilHittable(overview)
        overview.tap()

        let sessionPicker = app.segmentedControls["tabs.session"]
        XCTAssertTrue(sessionPicker.waitForExistence(timeout: 10))
        sessionPicker.buttons["Tabs"].tap()
        let regularCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "tab.select.")
        )
        XCTAssertTrue(regularCards.firstMatch.waitForExistence(timeout: 10))
        let firstRegularID = regularCards.firstMatch.identifier
        captureScreenshot(app, name: "Regular Tab Preview Grid")

        sessionPicker.buttons["Private"].tap()
        app.buttons["New Private Tab"].tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        overview.tap()
        XCTAssertTrue(sessionPicker.waitForExistence(timeout: 10))
        XCTAssertTrue(sessionPicker.buttons["Private"].isSelected)
        let privateCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "tab.select.")
        )
        XCTAssertTrue(privateCards.firstMatch.waitForExistence(timeout: 10))
        let privateID = privateCards.firstMatch.identifier
        XCTAssertNotEqual(privateID, firstRegularID)
        captureScreenshot(app, name: "Private Tab Preview Grid")

        sessionPicker.buttons["Tabs"].tap()
        let firstRegular = app.buttons[firstRegularID]
        XCTAssertTrue(firstRegular.waitForExistence(timeout: 10))
        firstRegular.tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        overview.tap()
        XCTAssertTrue(sessionPicker.waitForExistence(timeout: 10))
        XCTAssertTrue(sessionPicker.buttons["Tabs"].isSelected)
        XCTAssertEqual(try XCTUnwrap(app.buttons[firstRegularID].value as? String), "Selected tab")

        sessionPicker.buttons["Private"].tap()
        let closePrivateID = privateID.replacingOccurrences(of: "tab.select.", with: "tab.close.")
        let close = app.buttons[closePrivateID]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertFalse(app.buttons[privateID].exists)
        app.buttons["Done"].tap()
    }

    @MainActor
    private func assertLoadedHTTPSPage(in app: XCUIApplication, host: String) {
        let content = app.webViews.staticTexts.firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30))
        XCTAssertFalse(content.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if app.buttons["browser.address.open"].exists {
            let secureHost = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value BEGINSWITH %@", host + ", HTTPS"),
                object: app.buttons["browser.address.open"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [secureHost], timeout: 30), .completed)
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "Refresh"),
                object: app.buttons["duo.browser.refresh"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed)
        } else {
            XCTAssertTrue(app.buttons["HTTPS connection information"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.textFields["Address and search"].value as? String, host)
            waitUntilEnabled(app.buttons["Share page"])
        }
        XCTAssertFalse(app.staticTexts["Unable to Open Page"].exists)
    }

    @MainActor
    private func menuButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Browser menu"]
    }

    @MainActor
    private func openMenu(in app: XCUIApplication) {
        let button = menuButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        waitUntilHittable(button)
        button.tap()
        XCTAssertTrue(app.navigationBars["Browser Menu"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews["browser.menu.actions"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            list.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func navigate(_ input: String, in app: XCUIApplication) {
        let collapsed = app.buttons["browser.address.open"]
        if collapsed.exists { collapsed.tap() }
        let address = app.textFields["Address and search"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        app.buttons["Clear address"].tap()
        address.typeText(input)
        address.typeText("\n")
    }

    private func pixel(at point: CGPoint, in image: CGImage, window: CGRect) throws -> [UInt8] {
        let rect = CGRect(
            x: ((point.x - window.minX) * CGFloat(image.width) / window.width).rounded(.down),
            y: ((point.y - window.minY) * CGFloat(image.height) / window.height).rounded(.down),
            width: 1, height: 1
        )
        let cropped = try XCTUnwrap(image.cropping(to: rect))
        var result = [UInt8](repeating: 0, count: 4)
        try result.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(result.prefix(3))
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    @MainActor
    private func captureScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func captureFinalState(of app: XCUIApplication) {
        addTeardownBlock {
            await MainActor.run {
                self.captureScreenshot(app, name: "Final Browser State")
            }
        }
    }
}
