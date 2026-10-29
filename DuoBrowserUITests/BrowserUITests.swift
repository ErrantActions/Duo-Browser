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
    func testDuoNativeToolbarKeepsWebsiteVisibleAndDeliversNavigation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        captureFinalState(of: app)
        app.launch()
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
        print("Duo native toolbar: windowWidth=\(app.frame.width), webWidth=\(webpage.frame.width), actionX=\(next.frame.minX), actionWidth=\(next.frame.width)")
        XCTAssertGreaterThan(webpage.frame.width, app.frame.width * 0.6)
        XCTAssertGreaterThanOrEqual(next.frame.minX, webpage.frame.maxX - 2)
        XCTAssertLessThan(next.frame.width, app.frame.width * 0.25)
        XCTAssertTrue(app.buttons["Browser menu"].exists)
        XCTAssertTrue(app.buttons["duo.browser.back"].exists)
        XCTAssertTrue(app.buttons["duo.browser.refresh"].exists)
        XCTAssertFalse(app.buttons["duo.controls.open"].exists)
        captureScreenshot(app, name: "Native Duo Right-Edge Website Toolbar")

        next.tap()
        XCTAssertTrue(app.webViews.staticTexts["Record 2 of 3"].waitForExistence(timeout: 10))
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
    }

    @MainActor
    private func revealDuoControlsIfNeeded(in app: XCUIApplication) {
        let open = app.buttons["duo.controls.open"]
        if open.waitForExistence(timeout: 2) {
            open.tap()
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
        XCTAssertTrue(app.buttons["HTTPS connection information"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["Address and search"].value as? String, host)
        waitUntilEnabled(app.buttons["Share page"])
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
