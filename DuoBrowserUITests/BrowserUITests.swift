import XCTest

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
        let browserMenu = menuButton(in: app)
        waitUntilHittable(browserMenu)
        browserMenu.tap()
        app.buttons["Duo Site Permissions"].tap()
        app.buttons["Ask Again Next Time"].tap()
        app.buttons["Done"].tap()
        install.tap()
        let allow = app.buttons["Allow for This Site"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()
        let reserve = app.buttons["duo.control.reserve"]
        XCTAssertTrue(reserve.waitForExistence(timeout: 10))
        captureScreenshot(app, name: "Native Duo Panel")
        reserve.tap()
        let eventLog = app.webViews.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "duo.controlActivated")
        ).firstMatch
        XCTAssertTrue(eventLog.waitForExistence(timeout: 10))
        let clear = app.webViews.buttons["Clear Duo Panel"]
        clear.tap()
        let menu = menuButton(in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
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
    func testFavoriteCanBeSavedAndOpenedFromTheStartPage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        let menu = menuButton(in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["New Tab"].tap()
        navigate("https://example.com", in: app)
        XCTAssertTrue(app.webViews.staticTexts["Example Domain"].waitForExistence(timeout: 30))

        menu.tap()
        let addBookmark = app.buttons["Add Bookmark"]
        scrollTo(addBookmark, in: app)
        addBookmark.tap()
        let title = app.textFields["Bookmark title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(" UI-\(UUID().uuidString.prefix(6))")
        let savedTitle = try XCTUnwrap(title.value as? String)
        app.switches["bookmark.favorite"].tap()
        app.buttons["Save"].tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["Start Page"].tap()
        let favorite = app.buttons["Open favorite \(savedTitle)"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        captureScreenshot(app, name: "Start Page Favorites")
        favorite.tap()
        XCTAssertTrue(app.webViews.staticTexts["Example Domain"].waitForExistence(timeout: 30))
    }

    @MainActor
    func testHTTPSAddressAndBackForwardNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
        let menu = menuButton(in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        waitUntilHittable(menu)
        menu.tap()
        app.buttons["New Tab"].tap()

        navigate("example.com", in: app)
        let heading = app.webViews.staticTexts["Example Domain"]
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["HTTPS connection information"].exists)
        captureScreenshot(app, name: "Ordinary HTTPS Browsing")

        navigate("https://example.com/?duo=second", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        let back = app.buttons["Back"]
        waitUntilEnabled(back)
        back.tap()
        let forward = app.buttons["Forward"]
        waitUntilEnabled(forward)
        forward.tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
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
    private func menuButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["Browser menu"]
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func navigate(_ input: String, in app: XCUIApplication) {
        let address = app.textFields["Address and search"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        app.buttons["Clear address"].tap()
        address.typeText(input + "\n")
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
