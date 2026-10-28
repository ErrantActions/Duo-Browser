import XCTest
@testable import DuoBrowser

final class URLNormalizerTests: XCTestCase {
    func testBareHostUsesHTTPS() {
        guard case .website(let url) = URLNormalizer.resolve("example.com") else {
            return XCTFail("Expected a website")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testPreservesExplicitHTTPAndPath() {
        guard case .website(let url) = URLNormalizer.resolve(" http://example.com/a?q=b#c ") else {
            return XCTFail("Expected a website")
        }
        XCTAssertEqual(url.absoluteString, "http://example.com/a?q=b#c")
    }

    func testQueryIsEncodedWithoutInjectingParameters() {
        guard case .search(let url) = URLNormalizer.resolve("swift & webkit #ios") else {
            return XCTFail("Expected a search")
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.host, "duckduckgo.com")
        XCTAssertEqual(components?.queryItems?.count, 1)
        XCTAssertEqual(components?.queryItems?.first?.value, "swift & webkit #ios")
        XCTAssertNil(components?.fragment)
    }

    func testSupportsAlternativeSearchProvider() {
        guard case .search(let url) = URLNormalizer.resolve("swift ui", searchProvider: .google) else {
            return XCTFail("Expected a search")
        }
        XCTAssertEqual(url.host, "www.google.com")
    }

    func testEmptyInputDoesNothing() {
        XCTAssertEqual(URLNormalizer.resolve(" \n "), .empty)
    }

    func testSupportsLocalhostWithPort() {
        guard case .website(let url) = URLNormalizer.resolve("localhost:8443/path") else {
            return XCTFail("Expected a website")
        }
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, 8443)
    }

    func testSupportsIPv6() {
        guard case .website(let url) = URLNormalizer.resolve("[::1]:8443") else {
            return XCTFail("Expected an IPv6 website")
        }
        XCTAssertEqual(url.port, 8443)
    }

    func testAllowsUserInitiatedExternalLink() {
        guard case .external(let url) = URLNormalizer.resolve("mailto:person@example.com") else {
            return XCTFail("Expected an external link")
        }
        XCTAssertEqual(url.scheme, "mailto")
    }

    func testRejectsExecutableAndLocalSchemes() {
        for input in ["javascript:alert(1)", "data:text/html,test", "file:///etc/passwd", "about:blank"] {
            guard case .invalid = URLNormalizer.resolve(input) else {
                return XCTFail("Expected rejection of \(input)")
            }
        }
    }

    func testRejectsMalformedWebAddressesAndUnknownSchemes() {
        for input in ["https://", "https://bad host.com", "unknown://example.com", "https://user:pass@example.com"] {
            guard case .invalid = URLNormalizer.resolve(input) else {
                return XCTFail("Expected rejection of \(input)")
            }
        }
    }

    func testSingleWordAndDottedSearchPhraseUseSearch() {
        for input in ["webkit", "example.com documentation", "weather: Boston"] {
            guard case .search = URLNormalizer.resolve(input) else {
                return XCTFail("Expected search for \(input)")
            }
        }
    }

    func testStartPageCannotBeSearchOrExternalScheme() {
        XCTAssertNil(URLNormalizer.webURL(from: "search words"))
        XCTAssertNil(URLNormalizer.webURL(from: "tel:12345"))
        XCTAssertNil(URLNormalizer.webURL(from: "javascript:alert(1)"))
    }
}
