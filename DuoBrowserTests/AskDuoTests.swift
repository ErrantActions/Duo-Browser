import XCTest
import FoundationModels
import Combine
@testable import DuoBrowser

@MainActor
final class AskDuoTests: XCTestCase {
    func testAskDuoPresentationIsDisabledByDefault() {
        XCTAssertFalse(AskDuoModel.isEnabled)
        XCTAssertFalse(AskDuoModel.isVisible)
    }

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
        XCTAssertNil(assistant.failureCode)
        print("Ask Duo availability: onDeviceModelAvailable=\(AskDuoModel.modelUnavailableReason == nil)")
    }

    func testAssistantErrorsAreExplicitWithoutEchoingPrivateDiagnostics() {
        let failure = AskDuoModel.describeFailure(NSError(
            domain: "Fixture", code: 123,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE_DIAGNOSTIC_MARKER"]
        ))
        XCTAssertEqual(failure.code, "operation.Fixture.123")
        XCTAssertFalse(failure.message.contains("PRIVATE_DIAGNOSTIC_MARKER"))
        XCTAssertEqual(AskDuoModel.describeFailure(AskDuoError.staleContext).code, "page.validation")
    }

    func testConversationRetainsSixTurnsAndPromptsOnlyTwoShortenedExchanges() throws {
        var chat = AskDuoConversation()
        let link = AskDuoLink(id: 1, label: "Next", url: URL(string: "https://example.test/next?PRIVATE_NATIVE_HREF")!)
        for index in 0..<8 {
            try chat.append(
                question: "Question \(index): " + String(repeating: "q", count: 250),
                answer: AskDuoAnswer(text: "Answer \(index): " + String(repeating: "a", count: 700), link: link)
            )
        }
        XCTAssertEqual(chat.turns.count, 6)
        XCTAssertTrue(chat.turns[0].question.hasPrefix("Question 2:"))
        let prompt = try chat.promptData()
        let exchanges = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [[String: String]])
        XCTAssertEqual(exchanges.count, 2)
        XCTAssertEqual(Set(exchanges[0].keys), ["question", "answer"])
        XCTAssertTrue(exchanges[0]["question"]?.hasPrefix("Question 6:") == true)
        XCTAssertEqual(exchanges[0]["question"]?.count, 200)
        XCTAssertEqual(exchanges[0]["answer"]?.count, 300)
        XCTAssertFalse(prompt.contains("PRIVATE_NATIVE_HREF"))
        XCTAssertLessThanOrEqual(prompt.utf8.count, 8192)
    }

    func testConversationRejectsInvalidTurnsWithoutChangingHistory() throws {
        var chat = AskDuoConversation()
        XCTAssertThrowsError(try chat.append(question: "", answer: AskDuoAnswer(text: "Answer", link: nil)))
        XCTAssertThrowsError(try chat.append(question: String(repeating: "q", count: 401), answer: AskDuoAnswer(text: "Answer", link: nil)))
        XCTAssertThrowsError(try chat.append(question: "Question", answer: AskDuoAnswer(text: " \n ", link: nil)))
        XCTAssertThrowsError(try chat.append(question: "Question", answer: AskDuoAnswer(text: String(repeating: "a", count: 4001), link: nil)))
        XCTAssertTrue(chat.turns.isEmpty)
    }

    func testNewChatAndQuestionValidationAreExplicitAndPrivateChatIsBlocked() throws {
        let assistant = AskDuoModel()
        assistant.question = " "
        XCTAssertNil(assistant.validatedQuestion())
        XCTAssertNotNil(assistant.errorMessage)
        assistant.question = "  Explain the previous answer.  "
        XCTAssertEqual(assistant.validatedQuestion(), "Explain the previous answer.")
        assistant.allowsNavigation = true
        assistant.newChat()
        XCTAssertEqual(assistant.question, "")
        XCTAssertTrue(assistant.conversation.turns.isEmpty)
        XCTAssertFalse(assistant.allowsNavigation)
        XCTAssertNil(assistant.pendingQuestion)
        let manager = manager()
        defer { for tab in manager.tabs { tab.tearDown() } }
        let privateTab = try XCTUnwrap(manager.addTab(isPrivate: true))
        assistant.ask(privateTab, usingPage: false)
        XCTAssertTrue(assistant.errorMessage?.contains("Private Browsing") == true)
        XCTAssertFalse(assistant.isBusy)
    }

    func testRealAppleModelWhenRuntimeIsUsable() async throws {
        executionTimeAllowance = 90
        guard #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("Apple Intelligence reports unavailable. No live inference is claimed.")
        }
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        var options = GenerationOptions()
        options.maximumResponseTokens = 32
        do {
            let response = try await session.respond(to: "Reply with OK only.", options: options)
            XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } catch {
            #if targetEnvironment(simulator)
            if #available(iOS 27.0, *), error is LanguageModelError { throw error }
            if error is LanguageModelSession.GenerationError { throw error }
            let failure = error as NSError
            if failure.domain == "FoundationModels.LanguageModelError", failure.code == -1 {
                throw XCTSkip("Simulator model reports available but fails a minimal plain-text probe with FoundationModels.LanguageModelError -1. Live inference remains unverified; UI uses an explicitly labeled debug-only fixture, never a production fallback.")
            }
            #endif
            throw error
        }
        let answer = try await AskDuoModel.generate(
            question: "Write a brief friendly greeting.", context: nil, history: "[]", allowsNavigation: false
        )
        XCTAssertFalse(answer.text.isEmpty)
        XCTAssertNil(answer.link)
        let pageAnswer = try await AskDuoModel.generate(
            question: "Summarize the supplied excerpt.", context: try context(), history: "[]", allowsNavigation: false
        )
        XCTAssertFalse(pageAnswer.text.isEmpty)
        XCTAssertNil(pageAnswer.link)
        print("Ask Duo real Apple model probe: plainText=true, generalSchema=true, pageSchema=true")
    }

    func testGeneralChatPassesFollowUpHistoryWithoutPageAccessOrNavigation() async throws {
        let manager = manager()
        defer { for tab in manager.tabs { tab.tearDown() } }
        let tab = try XCTUnwrap(manager.selectedTab)
        var histories: [String] = []
        let assistant = AskDuoModel(availability: { nil }, generator: { _, context, history, navigation in
            XCTAssertNil(context)
            XCTAssertFalse(navigation)
            histories.append(history)
            return AskDuoAnswer(text: "Controlled test response.", link: nil)
        })
        let first = expectation(description: "First completed exchange")
        let firstSubscription = assistant.$conversation.dropFirst().prefix(1).sink { _ in first.fulfill() }
        assistant.question = "Hello"
        assistant.allowsNavigation = true
        assistant.ask(tab, usingPage: false)
        await fulfillment(of: [first], timeout: 5)
        firstSubscription.cancel()
        XCTAssertEqual(assistant.conversation.turns.count, 1)
        let second = expectation(description: "Follow-up completed exchange")
        let secondSubscription = assistant.$conversation.dropFirst().prefix(1).sink { _ in second.fulfill() }
        assistant.question = "Explain that more simply."
        assistant.ask(tab, usingPage: false)
        await fulfillment(of: [second], timeout: 5)
        secondSubscription.cancel()
        XCTAssertEqual(assistant.conversation.turns.count, 2)
        XCTAssertEqual(histories.count, 2)
        XCTAssertEqual(histories.first, "[]")
        XCTAssertTrue(histories.last?.contains("Hello") == true)
        XCTAssertNil(assistant.context)
        XCTAssertNil(assistant.answer?.link)
        assistant.clear()
        XCTAssertTrue(assistant.conversation.turns.isEmpty)
    }
}
