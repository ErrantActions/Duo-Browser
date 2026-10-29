import XCTest
@testable import DuoBrowser

final class DuoPanelLayoutTests: XCTestCase {
    func testCompactWidthsDoNotSqueezeTheWebpageBesideControls() {
        for width in [CGFloat(0), 320, 390, 430, 699] {
            let layout = DuoPanelLayout(availableWidth: width)
            XCTAssertFalse(layout.usesSidePane)
            XCTAssertNil(layout.panelWidth)
        }
    }

    func testSidePaneBeginsAtTheDocumentedThresholdAndUsesHalfTheWidth() throws {
        for width in [CGFloat(700), 744, 852, 1024, 1366] {
            let layout = DuoPanelLayout(availableWidth: width)
            let panel = try XCTUnwrap(layout.panelWidth)
            XCTAssertTrue(layout.usesSidePane)
            XCTAssertGreaterThanOrEqual(panel, 349.5)
            XCTAssertEqual(panel * 2 + 1, width, accuracy: 0.001)
        }
    }
}
