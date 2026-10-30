import Combine
import WebKit
import XCTest
@testable import DuoBrowser

@MainActor
final class SiteNavigationTests: XCTestCase, WKNavigationDelegate {
    private var loaded: XCTestExpectation?
    private let source = URL(string: "https://example.test/home")!

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.fulfill()
        loaded = nil
    }

    private func context(_ url: URL? = nil) -> SiteNavigationContext {
        let url = url ?? source
        return SiteNavigationContext(tabID: UUID(), epoch: UUID(), url: url, origin: DuoOrigin.canonical(url)!)
    }

    private func snapshot(_ entries: [[String: String]], context: SiteNavigationContext? = nil) throws -> SiteNavigationSnapshot {
        let context = context ?? self.context()
        return try SiteNavigationSnapshot(data: JSONSerialization.data(withJSONObject: [
            "url": context.url.absoluteString, "documentID": UUID().uuidString, "links": entries
        ]), context: context)
    }

    func testSnapshotFiltersUnsafeDestinationsAndStoresOnlyRouteDigests() throws {
        let page = try snapshot([
            ["label": "Products", "href": "https://example.test/products?category=parts"],
            ["label": "Duplicate", "href": "https://example.test/products?category=parts"],
            ["label": "Foreign", "href": "https://other.test/products"],
            ["label": "Script", "href": "javascript:alert(1)"],
            ["label": "Logout", "href": "https://example.test/logout"],
            ["label": "Action", "href": "https://example.test/items?action=delete"],
            ["label": "Token", "href": "https://example.test/items?token=PRIVATE_QUERY"],
            ["label": "Help", "href": "https://example.test/help"]
        ])
        XCTAssertEqual(page.links.map(\.label), ["Products", "Help"])
        XCTAssertEqual(page.links[0].id.count, 64)
        var profile = SiteNavigationPreferences()
        profile.pinned = [page.links[0].id]
        let encoded = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertFalse(encoded.contains("category"))
        XCTAssertFalse(encoded.contains("example.test"))
        XCTAssertEqual(try JSONDecoder().decode(SiteNavigationPreferences.self, from: Data(encoded.utf8)), profile)
    }

    func testPinHideOrderingAndPreferenceBounds() throws {
        let page = try snapshot((0..<5).map { ["label": "Page \($0)", "href": "https://example.test/page/\($0)"] })
        var profile = SiteNavigationPreferences()
        profile.pinned = [page.links[4].id]
        profile.hidden = [page.links[0].id]
        XCTAssertEqual(page.toolbarLinks(preferences: profile).map(\.label), ["Page 4", "Page 1"])
        profile.enabled = false
        XCTAssertTrue(page.toolbarLinks(preferences: profile).isEmpty)
        profile.pinned = page.links.prefix(3).map(\.id)
        XCTAssertThrowsError(try JSONDecoder().decode(SiteNavigationPreferences.self, from: JSONEncoder().encode(profile)))
        XCTAssertThrowsError(try JSONDecoder().decode(
            SiteNavigationPreferences.self, from: Data(#"{"enabled":true,"pinned":["not-a-digest"],"hidden":[]}"#.utf8)
        ))
        XCTAssertThrowsError(try snapshot(Array(repeating: ["label": "Page", "href": source.absoluteString], count: 13)))
    }

    func testDemoFragmentsRemainBoundToTheExactBundledFile() throws {
        let demo = try XCTUnwrap(DuoOrigin.demoURL)
        var target = try XCTUnwrap(URLComponents(url: demo, resolvingAgainstBaseURL: false))
        target.fragment = "nav-catalog"
        XCTAssertEqual(DuoOrigin.canonical(target.url), "duo-demo")
        target.query = "private=value"
        XCTAssertNil(DuoOrigin.canonical(target.url))
        XCTAssertNil(DuoOrigin.canonical(demo.deletingLastPathComponent().appendingPathComponent("other.html")))
    }

    func testOldSettingsMigrateAndPrivateChoicesNeverPersist() throws {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BrowserSettings())) as? [String: Any])
        raw.removeValue(forKey: "automaticallyDetectNavigation")
        raw.removeValue(forKey: "navigationProfiles")
        let migrated = try JSONDecoder().decode(BrowserSettings.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertTrue(migrated.automaticallyDetectNavigation)
        XCTAssertTrue(migrated.navigationProfiles.isEmpty)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
        let file = folder.appendingPathComponent("test.json")
        let library = BrowserLibrary(fileURL: file)
        let source = context()
        let privateModel = SiteNavigationModel(library: library, isPrivate: true)
        privateModel.setActive(false)
        privateModel.contextProvider = { source }
        privateModel.updatePreferences { $0.enabled = false }
        XCTAssertFalse(privateModel.preferences.enabled)
        XCTAssertTrue(library.settings.navigationProfiles.isEmpty)
        let regular = SiteNavigationModel(library: library, isPrivate: false)
        regular.setActive(false)
        regular.contextProvider = { source }
        regular.updatePreferences { $0.enabled = false }
        XCTAssertFalse(BrowserLibrary(fileURL: file).settings.navigationProfiles[source.origin]?.enabled ?? true)
        privateModel.tearDown()
        regular.tearDown()
    }

    private func page(demo: Bool = false) async throws -> WKWebView {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 800))
        view.navigationDelegate = self
        let ready = expectation(description: "Site navigation DOM loaded")
        loaded = ready
        if demo {
            let url = try XCTUnwrap(DuoOrigin.demoURL)
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
        view.loadHTMLString("""
            <header><nav aria-label="Primary navigation">
              <a href="/products">Products</a><a href="/help">Help</a>
              <a href="/logout">Sign Out</a><a href="https://other.test/">Foreign</a>
              <a href="/hidden" hidden>Hidden</a>
            </nav></header>
            <main><nav aria-label="Table of contents"><a href="/toc">Contents</a></nav></main>
            <footer><nav><a href="/footer">Footer</a><a href="/footer2">Other</a></nav></footer>
            """, baseURL: source)
        }
        await fulfillment(of: [ready], timeout: 15)
        if demo { try await view.evaluateJavaScript("document.querySelector('#site-navigation').hidden = false; true") }
        addTeardownBlock { await MainActor.run { view.stopLoading(); view.navigationDelegate = nil } }
        return view
    }

    private func run(_ view: WKWebView, _ arguments: [String: Any]) async throws -> Any? {
        try await view.callAsyncJavaScript("return " + SiteNavigationModel.script(), arguments: arguments, in: nil, contentWorld: SiteNavigationModel.world)
    }

    func testRealWebKitExtractionAndStaleLinkValidation() async throws {
        let view = try await page()
        let source = context(try XCTUnwrap(view.url))
        let result = try await run(view, ["mode": "capture", "allowDemo": false])
        let data = try XCTUnwrap((result as? String)?.data(using: .utf8))
        let page = try SiteNavigationSnapshot(data: data, context: source)
        XCTAssertEqual(page.links.map(\.label), ["Products", "Help"])
        let args: [String: Any] = [
            "mode": "validate", "allowDemo": false, "sourceURL": source.url.absoluteString,
            "documentID": page.documentID, "href": page.links[0].url.absoluteString
        ]
        let valid = try await run(view, args)
        XCTAssertEqual(valid as? Bool, true)
        try await view.evaluateJavaScript("document.querySelector('a').href = '/changed'; true")
        let stale = try await run(view, args)
        XCTAssertEqual(stale as? Bool, false)
    }

    func testControllerRefreshSuppressionAndDocumentReset() async throws {
        let view = try await page(demo: true)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
        let navigation = SiteNavigationModel(library: BrowserLibrary(fileURL: folder.appendingPathComponent("test.json")), isPrivate: false)
        defer { navigation.tearDown() }
        try navigation.install(on: view)
        let source = context(try XCTUnwrap(view.url))
        navigation.contextProvider = { source }
        let ready = expectation(description: "Detected primary navigation published")
        let subscription = navigation.$snapshot.compactMap { $0 }.prefix(1).sink { _ in ready.fulfill() }
        navigation.refresh()
        await fulfillment(of: [ready], timeout: 10)
        subscription.cancel()
        XCTAssertEqual(navigation.toolbarLinks.count, 2)
        navigation.setSuppressed(true)
        XCTAssertTrue(navigation.toolbarLinks.isEmpty)
        XCTAssertNotNil(navigation.snapshot)
        navigation.reset()
        XCTAssertNil(navigation.snapshot)
        XCTAssertFalse(navigation.isOpening)
    }

    func testResumingAfterReviewRearmsLiveNavigationUpdates() async throws {
        let view = try await page(demo: true)
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
        let navigation = SiteNavigationModel(library: BrowserLibrary(fileURL: folder.appendingPathComponent("test.json")), isPrivate: false)
        defer { navigation.tearDown() }
        try navigation.install(on: view)
        let source = context(try XCTUnwrap(view.url))
        navigation.contextProvider = { source }
        navigation.setActive(false)
        navigation.refreshForReview()
        let ready = expectation(description: "Active navigation after modal review")
        let initial = navigation.$snapshot.compactMap { $0 }.prefix(1).sink { _ in ready.fulfill() }
        navigation.setActive(true)
        await fulfillment(of: [ready], timeout: 10)
        initial.cancel()
        let updated = expectation(description: "Observed primary link label changed")
        let observation = navigation.$snapshot.compactMap { $0 }.filter {
            $0.links.first?.label == "Inventory"
        }.prefix(1).sink { _ in updated.fulfill() }
        try await view.evaluateJavaScript("document.querySelector('a').textContent = 'Inventory'; true")
        await fulfillment(of: [updated], timeout: 10)
        observation.cancel()
        XCTAssertEqual(navigation.toolbarLinks.first?.label, "Inventory")
    }
}
