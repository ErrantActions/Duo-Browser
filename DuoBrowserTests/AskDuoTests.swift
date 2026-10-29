import XCTest
@testable import DuoBrowser

@MainActor
final class AskDuoTests: XCTestCase {
    private let source = URL(string: "https://example.test/article?private-query-value")!

    private func context(
        text: String = "Visible article",
        links: [[String: String]] = [["label": "Next", "href": "https://example.test/next?private-link-value"]],
        sourceURL: URL? = nil, documentID: String = UUID().uuidString
    ) throws -> AskDuoContext {
        let url = sourceURL ?? source
        let data = try JSONSerialization.data(withJSONObject: [
            "url": url.absoluteString, "documentID": documentID,
            "title": "Article", "text": text, "truncated": false, "links": links
        ])
        return try AskDuoContext(data: data, tabID: UUID(), navigationID: UUID(), sourceURL: url)
    }

    func testPromptOmitsFullAddressesAndQueryValues() throws {
        let page = try context()
        let prompt = try page.promptData()
        XCTAssertTrue(prompt.contains("Visible article"))
        XCTAssertTrue(prompt.contains("Next"))
        XCTAssertFalse(prompt.contains("private-query-value"))
        XCTAssertFalse(prompt.contains("private-link-value"))
        XCTAssertEqual(page.links.first?.id, 1)
    }

    func testUnsafeAndDuplicateLinksCannotBecomeActions() throws {
        let page = try context(links: [
            ["label": "Script", "href": "javascript:alert(1)"],
            ["label": "HTTP", "href": "http://example.test/"],
            ["label": "Credentials", "href": "https://user:pass@example.test/"],
            ["label": "First", "href": "https://example.test/next"],
            ["label": "Duplicate", "href": "https://example.test/next"],
            ["label": "Second", "href": "https://example.test/another"]
        ])
        XCTAssertEqual(page.links.map(\.id), [1, 2])
        XCTAssertEqual(page.links.map(\.label), ["First", "Second"])
    }

    func testAnswerNeverCreatesAnUnapprovedOrInventedNavigation() throws {
        let page = try context()
        XCTAssertNil(try page.answer(text: "An answer", linkID: 0, allowsNavigation: false).link)
        XCTAssertEqual(try page.answer(text: "A suggestion", linkID: 1, allowsNavigation: true).link, page.links.first)
        XCTAssertThrowsError(try page.answer(text: "Action without permission", linkID: 1, allowsNavigation: false))
        XCTAssertThrowsError(try page.answer(text: "Invented", linkID: 2, allowsNavigation: true))
        XCTAssertThrowsError(try page.answer(text: "Invalid", linkID: -1, allowsNavigation: true))
        XCTAssertThrowsError(try page.answer(text: "", linkID: 0, allowsNavigation: false))
        XCTAssertThrowsError(try page.answer(text: String(repeating: "a", count: 4001), linkID: 0, allowsNavigation: false))
    }

    func testContextBoundsAndDocumentIdentityAreValidated() throws {
        let page = try context(text: String(repeating: "a", count: 2000))
        XCTAssertEqual(page.text.count, 1800)
        XCTAssertTrue(page.truncated)
        XCTAssertThrowsError(try context(documentID: "not-a-document-id"))
        XCTAssertThrowsError(try context(sourceURL: URL(string: "http://example.test/")!))
        XCTAssertThrowsError(try context(text: "", links: []))
        XCTAssertThrowsError(try context(links: Array(repeating: ["label": "Next", "href": "https://example.test/"], count: 13)))
        XCTAssertThrowsError(try AskDuoContext(
            data: Data(repeating: 65, count: 32_769),
            tabID: UUID(), navigationID: UUID(), sourceURL: source
        ))
    }

    private func manager() -> BrowserTabManager {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let library = BrowserLibrary(fileURL: directory.appendingPathComponent("test.json"))
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
        return BrowserTabManager(library: library)
    }

    func testAssistantSuspendsWebsiteCapabilitiesAcrossSceneReactivation() throws {
        let manager = manager()
        defer { for tab in manager.tabs { tab.tearDown() } }
        let tab = try XCTUnwrap(manager.selectedTab)
        let view = tab.webView
        tab.beginAssistantPresentation()
        tab.isActive = true
        XCTAssertTrue(tab.isShowingAssistant)
        XCTAssertFalse(tab.isActive)
        XCTAssertFalse(tab.bridge.canPresentNativeUI?() ?? true)
        tab.endAssistantPresentation(isActive: true)
        XCTAssertFalse(tab.isShowingAssistant)
        XCTAssertTrue(tab.isActive)
        XCTAssertTrue(tab.webView === view)
    }

    func testPrivateAndStartPagesAreBlockedBeforeReading() throws {
        let manager = manager()
        defer { for tab in manager.tabs { tab.tearDown() } }
        let tab = try XCTUnwrap(manager.selectedTab)
        XCTAssertNotNil(AskDuoPageReader.blockedReason(for: tab))
        let privateTab = try XCTUnwrap(manager.addTab(isPrivate: true))
        XCTAssertTrue(AskDuoPageReader.blockedReason(for: privateTab)?.contains("Private Browsing") == true)
    }

    func testNavigationEpochChangesOnPageReplacementAndClose() throws {
        let manager = manager()
        defer { for tab in manager.tabs { tab.tearDown() } }
        let tab = try XCTUnwrap(manager.selectedTab)
        let initial = tab.navigationID
        tab.goToStartPage()
        XCTAssertNotEqual(initial, tab.navigationID)
        let restored = tab.navigationID
        tab.navigationWillStart()
        XCTAssertNotEqual(restored, tab.navigationID)
        let navigating = tab.navigationID
        tab.tearDown()
        XCTAssertNotEqual(navigating, tab.navigationID)
    }

    func testClosingClearsLocalQuestionAndNavigationPermission() {
        let assistant = AskDuoModel()
        assistant.question = "Private local question"
        assistant.allowsNavigation = true
        assistant.clear()
        XCTAssertEqual(assistant.question, "")
        XCTAssertFalse(assistant.allowsNavigation)
        XCTAssertNil(assistant.context)
        XCTAssertFalse(assistant.hasApprovedContext)
        XCTAssertNil(assistant.answer)
        XCTAssertFalse(assistant.isBusy)
        print("Ask Duo availability: onDeviceModelAvailable=\(AskDuoModel.modelUnavailableReason == nil)")
    }
}
