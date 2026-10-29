import XCTest
@testable import DuoBrowser

final class DuoMessageValidatorTests: XCTestCase {
    private func data(_ configuration: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": "1.0", "documentId": UUID().uuidString,
            "method": "controls.set", "configuration": configuration
        ])
    }

    private var button: [String: Any] {
        ["id": "scan", "type": "button", "label": "Scan", "icon": "barcode.viewfinder"]
    }

    func testDecodesPanel() throws {
        let message = try DuoMessageValidator.decode(data(["id": "panel", "controls": [button]]))
        XCTAssertEqual(message.configuration?.controls.first?.id, "scan")
    }

    func testRejectsMalformedAndUnknownFields() throws {
        XCTAssertThrowsError(try DuoMessageValidator.decode(Data("not JSON".utf8)))
        XCTAssertThrowsError(try DuoMessageValidator.decode(data([
            "id": "panel", "controls": [button], "nativeSelector": "doSomething:"
        ])))
        var control = button
        control["hidden"] = true
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [control]])))
    }

    func testRejectsOversizedPayload() {
        XCTAssertThrowsError(try DuoMessageValidator.decode(Data(repeating: 32, count: 32_769)))
    }

    func testControlCountAndDuplicateLimits() throws {
        let controls = (0..<9).map { ["id": "c\($0)", "type": "button", "label": "Action"] }
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": controls])))
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [button, button]])))
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": []])))
    }

    func testRejectsUnsupportedIconAndType() throws {
        for field in ["icon", "type"] {
            var control = button
            control[field] = "unrestricted-system-action"
            XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [control]])))
        }
    }

    func testRejectsNumericBooleansAndOversizedLabels() throws {
        var control = button
        control["enabled"] = 1
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [control]])))
        control = button
        control["label"] = String(repeating: "A", count: 81)
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [control]])))
    }

    func testToggleAndSegmentValues() throws {
        let controls: [[String: Any]] = [
            ["id": "toggle", "type": "toggle", "label": "Enabled", "value": true],
            ["id": "segment", "type": "segmented", "label": "Count", "value": "a",
             "options": [["id": "a", "label": "A"], ["id": "b", "label": "B"]]]
        ]
        let result = try DuoMessageValidator.decode(data(["id": "panel", "controls": controls]))
        XCTAssertEqual(result.configuration?.controls[0].value, .bool(true))
        var invalid = controls[1]
        invalid["value"] = "missing"
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [invalid]])))
    }

    func testRejectsDeepPayloadAndEmptyVisiblePanels() throws {
        var value: [String: Any] = ["key": true]
        for _ in 0..<8 { value = ["key": value] }
        var control = button
        control["payload"] = value
        XCTAssertThrowsError(try DuoMessageValidator.decode(data(["id": "panel", "controls": [control]])))
        XCTAssertThrowsError(try DuoMessageValidator.decode(data([
            "id": "panel", "controls": [["id": "space", "type": "spacer", "label": "Space"]]
        ])))
    }

    func testScannerRequiresTokenAndRequestIdentifier() throws {
        let incomplete = try JSONSerialization.data(withJSONObject: [
            "version": "1.0", "documentId": UUID().uuidString, "method": "scanner.request"
        ])
        XCTAssertThrowsError(try DuoMessageValidator.decode(incomplete))
    }

    func testNativeToolbarKeepsEveryActionAndExcludesOnlyLayoutSpacers() {
        let previous = DuoControl(id: "previous", type: .button, label: "Previous")
        let spacer = DuoControl(id: "space", type: .spacer, label: "Space")
        let toggle = DuoControl(id: "toggle", type: .toggle, label: "Flag")
        let panel = DuoPanel(id: "navigation", controls: [previous, spacer, toggle])
        XCTAssertEqual(panel.toolbarControls, [previous, toggle])
    }
}
