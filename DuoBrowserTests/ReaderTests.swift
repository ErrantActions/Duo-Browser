import PDFKit
import XCTest
@testable import DuoBrowser

@MainActor
final class ReaderTests: XCTestCase {
    private let source = URL(string: "https://example.test/article?private-query-value")!

    private func article(
        blocks: [[String: Any]] = [
            ["kind": "heading", "level": 1, "text": "Article title"],
            ["kind": "body", "level": 0, "text": "A readable paragraph for the local reading view."]
        ]
    ) throws -> ReaderDocument {
        let data = try JSONSerialization.data(withJSONObject: [
            "url": source.absoluteString, "documentID": UUID().uuidString,
            "title": "Article title", "language": "en-US", "blocks": blocks, "truncated": false
        ])
        return try ReaderDocument(data: data, tabID: UUID(), navigationID: UUID(), sourceURL: source)
    }

    func testReadingSnapshotRemovesDuplicateTitleAndCountsWords() throws {
        let document = try article()
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.wordCount, 8)
        XCTAssertEqual(document.minutesToRead, 1)
        XCTAssertEqual(document.attribution, "example.test")
        XCTAssertFalse(document.attribution.contains("private-query-value"))
    }

    func testReadingBoundsRejectMalformedOrOversizedDocuments() throws {
        XCTAssertThrowsError(try article(blocks: []))
        XCTAssertThrowsError(try article(blocks: [["kind": "body", "level": 0, "text": ""]]))
        XCTAssertThrowsError(try article(blocks: [["kind": "unknown", "level": 0, "text": "Text"]]))
        XCTAssertThrowsError(try article(blocks: [["kind": "body", "level": 0, "text": String(repeating: "a", count: 4001)]]))
        XCTAssertThrowsError(try article(blocks: Array(repeating: ["kind": "body", "level": 0, "text": "Text"], count: 401)))
        XCTAssertThrowsError(try ReaderDocument(
            data: Data(repeating: 65, count: 262_145), tabID: UUID(), navigationID: UUID(), sourceURL: source
        ))
        XCTAssertFalse(ReaderDocument.allowedSource(URL(string: "file:///private.txt")!))
        XCTAssertFalse(ReaderDocument.allowedSource(URL(string: "https://user:pass@example.test/")!))
        XCTAssertTrue(ReaderDocument.allowedSource(URL(string: "http://example.test/article")!))
    }

    func testReadingPDFIsPaginatedSearchableAndOmitsURLQueryMetadata() throws {
        let document = try article(blocks: Array(repeating: [
            "kind": "body", "level": 0, "text": String(repeating: "Readable text for a page. ", count: 40)
        ], count: 20))
        let data = try ReadingPDF.data(for: document)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertLessThanOrEqual(pdf.pageCount, 64)
        XCTAssertTrue(pdf.string?.contains("Article title") == true)
        XCTAssertTrue(pdf.string?.contains("Readable text") == true)
        XCTAssertFalse(pdf.string?.contains("private-query-value") == true)
    }

    func testOldSettingsDecodeWithSafeReaderDefaults() throws {
        let encoded = try JSONEncoder().encode(BrowserSettings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "reader")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(BrowserSettings.self, from: oldData)
        XCTAssertEqual(decoded.reader.fontSize, 19)
        XCTAssertEqual(decoded.reader.theme, .paper)
        XCTAssertEqual(decoded.searchProvider, .duckDuckGo)
        XCTAssertEqual(decoded.maximumTabs, 20)
    }

    func testReaderPreferencesRoundTripAndRejectUnsafeFontSizes() throws {
        var settings = BrowserSettings()
        settings.reader.fontSize = 24
        settings.reader.theme = .sepia
        let restored = try JSONDecoder().decode(BrowserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.reader, settings.reader)
        XCTAssertThrowsError(try JSONDecoder().decode(
            ReaderPreferences.self, from: Data(#"{"fontSize":300,"theme":"paper"}"#.utf8)
        ))
    }

    func testReaderSuspendsCapabilitiesAndStopsWithoutSpeaking() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = BrowserTabManager(library: BrowserLibrary(fileURL: directory.appendingPathComponent("test.json")))
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
        defer { for tab in manager.tabs { tab.tearDown() } }
        let tab = try XCTUnwrap(manager.selectedTab)
        tab.beginReaderPresentation()
        tab.isActive = true
        XCTAssertFalse(tab.isActive)
        XCTAssertFalse(tab.bridge.canPresentNativeUI?() ?? true)
        tab.endPageToolPresentation(isActive: true)
        XCTAssertTrue(tab.isActive)
        XCTAssertFalse(tab.isShowingReader)
        let reader = ReaderModel()
        reader.stopSpeech()
        reader.close()
        XCTAssertEqual(reader.speechState, .stopped)
        XCTAssertNil(reader.document)
        XCTAssertNil(reader.export)
    }
}
