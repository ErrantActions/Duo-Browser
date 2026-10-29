import WebKit
import UIKit
import XCTest
@testable import DuoBrowser

@MainActor
final class ScannerTests: XCTestCase, WKNavigationDelegate {
    private var loaded: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.fulfill()
        loaded = nil
    }

    private func page() async throws -> WKWebView {
        let view = WKWebView()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow))
        view.frame = window.bounds
        window.addSubview(view)
        addTeardownBlock {
            await MainActor.run {
                view.stopLoading()
                view.navigationDelegate = nil
                view.removeFromSuperview()
            }
        }
        try ScannerInput.install(on: view)
        view.navigationDelegate = self
        let ready = expectation(description: "Scanner input fixture loaded")
        loaded = ready
        view.loadHTMLString("""
            <form id="form" action="https://example.test/lookup">
              <input id="target" aria-label="Barcode" value="abcdef">
              <input id="required" required>
              <textarea id="notes"></textarea>
            </form>
            <input id="secret" type="password"><input id="payment" autocomplete="cc-number">
            <script>
              window.events = []; window.submissions = 0;
              for (const type of ["beforeinput","input","change","keydown","keypress","keyup"]) {
                document.querySelector("#target").addEventListener(type, event => {
                  window.events.push(event.type);
                });
              }
              document.querySelector("#form").onsubmit = event => {
                event.preventDefault(); window.submissions++;
              };
            </script>
            """, baseURL: URL(string: "https://example.test/"))
        await fulfillment(of: [ready], timeout: 15)
        try await view.evaluateJavaScript("document.querySelector('#target').focus(); document.querySelector('#target').setSelectionRange(2, 4);")
        return view
    }

    private func capture(_ view: WKWebView) async throws -> String {
        let value = try await ScannerInput.call(on: view, arguments: ["mode": "capture"])
        return try XCTUnwrap(value as? String)
    }

    private func apply(_ view: WKWebView, token: String, insertion: String = "selection", suffix: String = "none", value: String = "123", deadline: Double = 5000) async throws {
        let result = try await ScannerInput.call(on: view, arguments: [
            "mode": "apply", "token": token, "sourceURL": try XCTUnwrap(view.url).absoluteString,
            "value": value, "insertion": insertion, "suffix": suffix,
            "expiresAt": Date().timeIntervalSince1970 * 1000 + deadline
        ])
        XCTAssertEqual(result as? Bool, true)
    }

    private func reject(_ action: () async throws -> Void) async {
        do {
            try await action()
            XCTFail("Unsafe or stale scanner input was accepted")
        } catch {
            XCTAssertTrue(error is WKError)
        }
    }

    func testScannerPreferencesMigrateAndRoundTripWithoutEnablingSubmission() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BrowserSettings())) as? [String: Any])
        object.removeValue(forKey: "scanner")
        let old = try JSONDecoder().decode(BrowserSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.scanner.compact)
        XCTAssertEqual(old.scanner.suffix, .none)
        XCTAssertEqual(old.scanner.insertion, .selection)
        var settings = old
        settings.scanner.compact = false
        settings.scanner.feedback = false
        settings.scanner.formats = .barcodes
        settings.scanner.insertion = .append
        settings.scanner.suffix = .submit
        XCTAssertEqual(try JSONDecoder().decode(BrowserSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    func testScannerSuspendsWebsiteCapabilitiesUntilDismissal() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = BrowserTabManager(library: BrowserLibrary(fileURL: folder.appendingPathComponent("test.json")))
        addTeardownBlock { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
        defer { for tab in manager.tabs { tab.tearDown() } }
        let tab = try XCTUnwrap(manager.selectedTab)
        tab.beginScannerPresentation()
        tab.isActive = true
        XCTAssertFalse(tab.isActive)
        XCTAssertTrue(tab.isShowingScanner)
        XCTAssertFalse(tab.bridge.canPresentNativeUI?() ?? true)
        tab.endPageToolPresentation(isActive: true)
        XCTAssertFalse(tab.isShowingScanner)
        XCTAssertTrue(tab.isActive)
    }

    func testScannerInsertsAtSelectionAndSendsInputChangeAndEnterOnce() async throws {
        let view = try await page()
        let token = try await capture(view)
        try await apply(view, token: token, suffix: "enter")
        let text = try await view.evaluateJavaScript("document.querySelector('#target').value")
        let events = try await view.evaluateJavaScript("window.events.join(',')")
        XCTAssertEqual(text as? String, "ab123ef")
        XCTAssertEqual(events as? String, "beforeinput,input,change,keydown,keypress,keyup")
        await reject { try await self.apply(view, token: token) }
        let replacement = try await capture(view)
        try await apply(view, token: replacement, insertion: "replace", value: "987")
        let appended = try await capture(view)
        try await apply(view, token: appended, insertion: "append", value: "654")
        let final = try await view.evaluateJavaScript("document.querySelector('#target').value")
        XCTAssertEqual(final as? String, "987654")
        let cancelled = try await capture(view)
        await ScannerInput.clear(on: view, token: cancelled)
        await reject { try await self.apply(view, token: cancelled) }
        try await view.evaluateJavaScript("document.querySelector('#form').setAttribute('action', 'http://['); true")
        let ordinaryInput = try await capture(view)
        try await apply(view, token: ordinaryInput, insertion: "append", value: "ZZ")
        let noSubmissionDependency = try await view.evaluateJavaScript("document.querySelector('#target').value")
        XCTAssertEqual(noSubmissionDependency as? String, "987654ZZ", "Plain input must not depend on a valid form action")
    }

    func testScannerRejectsChangedSensitiveHiddenAndOversizedTargets() async throws {
        let view = try await page()
        let expired = try await capture(view)
        await reject { try await self.apply(view, token: expired, deadline: -1) }
        let sanitized = try await capture(view)
        await reject { try await self.apply(view, token: sanitized, insertion: "replace", value: "123\n456") }
        let preserved = try await view.evaluateJavaScript("document.querySelector('#target').value")
        XCTAssertEqual(preserved as? String, "abcdef", "Browser input sanitization must not silently corrupt a barcode")
        let token = try await capture(view)
        try await view.evaluateJavaScript("document.querySelector('#target').value = 'changed'")
        await reject { try await self.apply(view, token: token) }
        for mutation in [
            "document.querySelector('#target').readOnly = true",
            "document.querySelector('#target').style.display = 'none'",
            "document.querySelector('#target').type = 'password'",
            "document.querySelector('#target').maxLength = 1",
            "history.replaceState(null, '', '/different')",
            "document.querySelector('#secret').focus()"
        ] {
            try await view.evaluateJavaScript("""
                history.replaceState(null, '', '/');
                var field = document.querySelector('#target');
                field.readOnly = false; field.style.display = ''; field.type = 'text'; field.maxLength = 100;
                field.value = ''; field.focus();
                """)
            let current = try await capture(view)
            try await view.evaluateJavaScript(mutation)
            await reject { try await self.apply(view, token: current) }
        }
        try await view.evaluateJavaScript("document.querySelector('#payment').focus()")
        await reject { _ = try await self.capture(view) }
    }

    func testScannerFormSubmissionValidatesAndHonorsCanceledEnter() async throws {
        let view = try await page()
        var token = try await capture(view)
        try await apply(view, token: token, insertion: "replace", suffix: "submit")
        var count = try await view.evaluateJavaScript("window.submissions")
        XCTAssertEqual(count as? Int, 0, "Required fields must retain browser validation")
        try await view.evaluateJavaScript("document.querySelector('#required').value = 'ok'; document.querySelector('#target').focus()")
        token = try await capture(view)
        try await apply(view, token: token, suffix: "submit")
        count = try await view.evaluateJavaScript("window.submissions")
        XCTAssertEqual(count as? Int, 1)
        try await view.evaluateJavaScript("document.querySelector('#target').onkeydown = event => event.preventDefault(); true")
        token = try await capture(view)
        try await apply(view, token: token, suffix: "submit")
        count = try await view.evaluateJavaScript("window.submissions")
        XCTAssertEqual(count as? Int, 1)
        try await view.evaluateJavaScript("document.querySelector('#form').action = 'https://other.test/lookup'")
        token = try await capture(view)
        await reject { try await self.apply(view, token: token, suffix: "submit") }
    }

    func testScannerPreferencesPersistToDiskWithoutChangingOtherSettings() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = folder.appendingPathComponent("test.json")
        addTeardownBlock { if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) } }
        let library = BrowserLibrary(fileURL: file)
        var settings = library.settings
        settings.scanner.insertion = .replace
        settings.scanner.suffix = .submit
        XCTAssertTrue(library.updateSettings(settings))
        let restored = BrowserLibrary(fileURL: file)
        XCTAssertEqual(restored.settings, settings)
        XCTAssertEqual(restored.settings.scanner.suffix, .submit)
    }
}
