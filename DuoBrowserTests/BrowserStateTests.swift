import WebKit
import XCTest
@testable import DuoBrowser

@MainActor
final class BrowserStateTests: XCTestCase {
    private var directory: URL?

    private func library() -> BrowserLibrary {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.directory = directory
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return BrowserLibrary(fileURL: directory.appendingPathComponent("test.json"))
    }

    func testTabsAreIndependentAndFinalTabIsReplaced() throws {
        let manager = BrowserTabManager(library: library())
        let first = try XCTUnwrap(manager.selectedTab)
        let second = try XCTUnwrap(manager.addTab())
        XCTAssertFalse(first.webView === second.webView)
        XCTAssertNotEqual(first.id, second.id)
        manager.close(second.id)
        XCTAssertEqual(manager.selectedTab?.id, first.id)
        manager.close(first.id)
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertNotEqual(manager.selectedTab?.id, first.id)
    }

    func testPrivateSessionIsNonpersistentAndNotRestored() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        let tab = try XCTUnwrap(manager.addTab(isPrivate: true))
        XCTAssertFalse(tab.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(library.snapshot.session.tabs.count, 1)
        XCTAssertTrue(manager.tabs.first?.webView.configuration.websiteDataStore.isPersistent == true)
        for tab in manager.tabs { tab.tearDown() }
    }

    func testRestoredURLsSurviveSavingBeforeWebKitLoads() throws {
        let library = library()
        let first = try XCTUnwrap(URL(string: "https://first.invalid/article"))
        let second = try XCTUnwrap(URL(string: "https://second.invalid/search?q=duo"))
        library.saveSession(SavedSession(
            tabs: [
                RestoredTab(url: first, requestsDesktopSite: false),
                RestoredTab(url: second, requestsDesktopSite: true)
            ],
            selectedIndex: 1
        ))

        let manager = BrowserTabManager(library: library)
        defer { for tab in manager.tabs { tab.tearDown() } }
        // No run-loop turn or successful navigation is needed to preserve the saved addresses.
        XCTAssertEqual(library.snapshot.session.tabs.map(\.url), [first, second])
        XCTAssertEqual(library.snapshot.session.selectedIndex, 1)
        XCTAssertEqual(manager.selectedTab?.id, manager.tabs[1].id)
        XCTAssertFalse(manager.tabs[0].isActive)
        XCTAssertTrue(manager.tabs[1].isActive)
        XCTAssertTrue(library.snapshot.session.tabs[1].requestsDesktopSite)

        manager.saveSession()
        let reloaded = BrowserLibrary(fileURL: try XCTUnwrap(directory).appendingPathComponent("test.json"))
        XCTAssertEqual(reloaded.snapshot.session.tabs.map(\.url), [first, second])
    }

    func testFirstNavigationIsSavedBeforeItFinishes() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        defer { for tab in manager.tabs { tab.tearDown() } }
        let url = try XCTUnwrap(URL(string: "https://pending.invalid/path"))
        let tab = try XCTUnwrap(manager.selectedTab)
        tab.load(url)
        XCTAssertEqual(library.snapshot.session.tabs.first?.url, url)
        XCTAssertEqual(tab.restorableURL, url)
        tab.goToStartPage()
        XCTAssertNil(library.snapshot.session.tabs.first?.url)
    }

    func testClosedTabIgnoresLateCallbacksAndNavigation() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        let tab = try XCTUnwrap(manager.selectedTab)
        manager.close(tab.id)
        defer { for tab in manager.tabs { tab.tearDown() } }

        tab.isActive = true
        tab.load(try XCTUnwrap(URL(string: "https://closed.invalid")))
        tab.navigationWillStart()
        tab.navigationDidFinish()
        tab.navigationDidFail(URLError(.notConnectedToInternet))
        tab.contentProcessDidTerminate()
        XCTAssertTrue(tab.isClosed)
        XCTAssertFalse(tab.isActive)
        XCTAssertTrue(tab.showingStartPage)
        XCTAssertNil(tab.restorableURL)
        XCTAssertNil(tab.navigationError)
        XCTAssertTrue(library.snapshot.history.isEmpty)
    }

    func testClosingLastPrivateTabReplacesItsTemporaryStore() throws {
        let manager = BrowserTabManager(library: library())
        let first = try XCTUnwrap(manager.addTab(isPrivate: true))
        let originalStore = first.webView.configuration.websiteDataStore
        manager.close(first.id)
        let next = try XCTUnwrap(manager.addTab(isPrivate: true))
        defer { for tab in manager.tabs { tab.tearDown() } }
        XCTAssertFalse(originalStore === next.webView.configuration.websiteDataStore)
        XCTAssertFalse(next.webView.configuration.websiteDataStore.isPersistent)
    }

    func testSwitchingTabsRetainsWebViewsAndPersistsOnlyRegularSelection() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        defer { for tab in manager.tabs { tab.tearDown() } }
        let first = try XCTUnwrap(manager.selectedTab)
        let firstWebView = first.webView
        let privateTab = try XCTUnwrap(manager.addTab(isPrivate: true))
        let second = try XCTUnwrap(manager.addTab())
        let secondWebView = second.webView

        manager.select(first.id)
        XCTAssertTrue(manager.selectedTab?.webView === firstWebView)
        XCTAssertTrue(first.isActive)
        XCTAssertFalse(privateTab.isActive)
        XCTAssertFalse(second.isActive)
        XCTAssertEqual(library.snapshot.session.selectedIndex, 0)

        manager.select(second.id)
        XCTAssertTrue(manager.selectedTab?.webView === secondWebView)
        XCTAssertFalse(first.isActive)
        XCTAssertTrue(second.isActive)
        XCTAssertEqual(library.snapshot.session.tabs.count, 2)
        XCTAssertEqual(library.snapshot.session.selectedIndex, 1)

        manager.select(privateTab.id)
        XCTAssertEqual(library.snapshot.session.tabs.count, 2)
        XCTAssertEqual(library.snapshot.session.selectedIndex, 0)
    }

    func testClearingDataSerializesTabsAndDoesNotLoadCustomStartPage() async throws {
        let library = library()
        var settings = library.settings
        settings.startPageAddress = "https://startup.invalid"
        library.updateSettings(settings)
        let url = try XCTUnwrap(URL(string: "https://history.invalid"))
        library.recordVisit(title: "History", url: url, isPrivate: false)
        library.saveBookmark(Bookmark(title: "Saved", url: url))
        library.addToReadingList(title: "Later", url: url)
        library.setPermissions(SitePermissions(controls: .allow), for: "https://history.invalid")

        let cleanupStarted = expectation(description: "Website cleanup started")
        var finishCleanup: CheckedContinuation<Void, Never>?
        var cleanupCalls = 0
        let manager = BrowserTabManager(library: library, removeWebsiteData: {
            cleanupCalls += 1
            await withCheckedContinuation { continuation in
                finishCleanup = continuation
                cleanupStarted.fulfill()
            }
        })
        let closedTab = try XCTUnwrap(manager.selectedTab)
        let clearTask = Task { await manager.clearWebsiteData() }
        await fulfillment(of: [cleanupStarted], timeout: 5)
        defer { finishCleanup?.resume() }

        XCTAssertTrue(manager.isClearingData)
        XCTAssertTrue(closedTab.isClosed)
        XCTAssertTrue(manager.tabs.isEmpty)
        XCTAssertNil(manager.selectedID)
        XCTAssertTrue(library.snapshot.session.tabs.isEmpty)
        let persisted = BrowserLibrary(fileURL: try XCTUnwrap(directory).appendingPathComponent("test.json"))
        XCTAssertTrue(persisted.snapshot.session.tabs.isEmpty)
        XCTAssertNil(manager.addTab())
        XCTAssertNotNil(manager.notice)
        await manager.clearWebsiteData()
        XCTAssertEqual(cleanupCalls, 1)

        finishCleanup?.resume()
        finishCleanup = nil
        await clearTask.value
        defer { for tab in manager.tabs { tab.tearDown() } }
        let freshTab = try XCTUnwrap(manager.selectedTab)
        XCTAssertFalse(manager.isClearingData)
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertTrue(freshTab.showingStartPage)
        XCTAssertNil(freshTab.restorableURL)
        XCTAssertNil(freshTab.webView.url)
        XCTAssertTrue(library.snapshot.history.isEmpty)
        XCTAssertTrue(library.snapshot.permissions.isEmpty)
        XCTAssertEqual(library.snapshot.bookmarks.count, 1)
        XCTAssertEqual(library.snapshot.readingList.count, 1)
        XCTAssertEqual(library.settings.startPageAddress, settings.startPageAddress)
    }

    func testTabLimitIsEnforced() {
        let library = library()
        var settings = library.settings
        settings.maximumTabs = 1
        library.updateSettings(settings)
        let manager = BrowserTabManager(library: library)
        XCTAssertNil(manager.addTab())
        XCTAssertNotNil(manager.notice)
        for tab in manager.tabs { tab.tearDown() }
    }

    func testRecentlyClosedRegularTabReopensWithItsDesktopPreference() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        defer { for tab in manager.tabs { tab.tearDown() } }
        let url = try XCTUnwrap(URL(string: "https://reopen.invalid/article"))
        let original = try XCTUnwrap(manager.addTab(url: url, desktop: true, pageZoom: 1.75))
        manager.close(original.id)
        let entry = try XCTUnwrap(manager.recentlyClosedTabs.first)
        XCTAssertEqual(entry.url, url)
        XCTAssertTrue(entry.requestsDesktopSite)
        XCTAssertEqual(entry.pageZoom, 1.75)

        let encoded = try JSONEncoder().encode(library.snapshot)
        XCTAssertFalse(try XCTUnwrap(String(data: encoded, encoding: .utf8)).contains("reopen.invalid"))
        let reopened = try XCTUnwrap(manager.reopen(entry.id))
        XCTAssertNotEqual(reopened.id, original.id)
        XCTAssertFalse(reopened.webView === original.webView)
        XCTAssertFalse(reopened.isPrivate)
        XCTAssertEqual(reopened.restorableURL, url)
        XCTAssertTrue(reopened.requestsDesktopSite)
        XCTAssertEqual(reopened.pageZoom, 1.75)
        XCTAssertTrue(manager.recentlyClosedTabs.isEmpty)
    }

    func testPrivateAndStartTabsDoNotEnterRecentlyClosedList() throws {
        let manager = BrowserTabManager(library: library())
        let start = try XCTUnwrap(manager.selectedTab)
        manager.close(start.id)
        XCTAssertTrue(manager.recentlyClosedTabs.isEmpty)
        let privateTab = try XCTUnwrap(manager.addTab(
            url: try XCTUnwrap(URL(string: "https://private.invalid")), isPrivate: true
        ))
        manager.close(privateTab.id)
        XCTAssertTrue(manager.recentlyClosedTabs.isEmpty)
        for tab in manager.tabs { tab.tearDown() }
    }

    func testCloseAllOnlyClosesTheRequestedSession() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        defer { for tab in manager.tabs { tab.tearDown() } }
        let regular = try XCTUnwrap(manager.selectedTab)
        let privateTab = try XCTUnwrap(manager.addTab(isPrivate: true))
        let privateWebView = privateTab.webView
        XCTAssertNotNil(manager.addTab())
        manager.closeAll(isPrivate: false)
        XCTAssertEqual(manager.tabs.map(\.id), [privateTab.id])
        XCTAssertTrue(manager.selectedTab?.webView === privateWebView)
        XCTAssertTrue(regular.isClosed)
        XCTAssertFalse(privateTab.isClosed)
        XCTAssertTrue(library.snapshot.session.tabs.isEmpty)

        manager.closeAll(isPrivate: true)
        XCTAssertEqual(manager.tabs.count, 1)
        let replacement = try XCTUnwrap(manager.selectedTab)
        XCTAssertTrue(replacement.isPrivate)
        XCTAssertTrue(replacement.showingStartPage)
        XCTAssertTrue(privateTab.isClosed)
        XCTAssertFalse(replacement.webView.configuration.websiteDataStore === privateWebView.configuration.websiteDataStore)
        XCTAssertTrue(manager.recentlyClosedTabs.isEmpty)
    }

    func testPageZoomRetainsWebViewAndPersistsWithItsTab() throws {
        let library = library()
        let manager = BrowserTabManager(library: library)
        let tab = try XCTUnwrap(manager.selectedTab)
        let webView = tab.webView
        tab.setPageZoom(1.5)
        XCTAssertEqual(tab.pageZoom, 1.5)
        XCTAssertEqual(webView.pageZoom, CGFloat(1.5))
        XCTAssertTrue(tab.webView === webView)
        XCTAssertNil(webView.url)
        XCTAssertEqual(library.snapshot.session.tabs.first?.pageZoom, 1.5)

        let restored = BrowserTabManager(library: library)
        XCTAssertEqual(restored.selectedTab?.pageZoom, 1.5)
        XCTAssertEqual(restored.selectedTab?.webView.pageZoom, CGFloat(1.5))
        for value in [Double.nan, .infinity, 0.25, 3.25] {
            tab.alert = nil
            tab.setPageZoom(value)
            XCTAssertEqual(tab.pageZoom, 1.5)
            XCTAssertNotNil(tab.alert)
        }
        for tab in manager.tabs { tab.tearDown() }
        for tab in restored.tabs { tab.tearDown() }
    }

    func testReopenAtTabLimitKeepsClosedEntryForAnotherAttempt() throws {
        let library = library()
        var settings = library.settings
        settings.maximumTabs = 1
        library.updateSettings(settings)
        let manager = BrowserTabManager(library: library)
        defer { for tab in manager.tabs { tab.tearDown() } }
        let original = try XCTUnwrap(manager.selectedTab)
        original.load(try XCTUnwrap(URL(string: "https://limit.invalid")))
        manager.close(original.id)
        let entry = try XCTUnwrap(manager.recentlyClosedTabs.first)
        XCTAssertNil(manager.reopen(entry.id))
        XCTAssertEqual(manager.recentlyClosedTabs.first?.id, entry.id)
        XCTAssertNotNil(manager.notice)
        settings.maximumTabs = 2
        library.updateSettings(settings)
        XCTAssertNotNil(manager.reopen(entry.id))
        XCTAssertTrue(manager.recentlyClosedTabs.isEmpty)
    }

    func testRecentlyClosedListIsBoundedAndClearedWithBrowsingData() async throws {
        let library = library()
        var settings = library.settings
        settings.maximumTabs = 2
        library.updateSettings(settings)
        let manager = BrowserTabManager(library: library, removeWebsiteData: {})
        defer { for tab in manager.tabs { tab.tearDown() } }
        for host in ["first.invalid", "second.invalid", "third.invalid"] {
            let tab = try XCTUnwrap(manager.selectedTab)
            tab.load(try XCTUnwrap(URL(string: "https://\(host)")))
            manager.close(tab.id)
        }
        XCTAssertEqual(manager.recentlyClosedTabs.map(\.url.host), ["third.invalid", "second.invalid"])
        await manager.clearWebsiteData()
        XCTAssertTrue(manager.recentlyClosedTabs.isEmpty)
    }

    func testHistoryExcludesPrivateAndUpdatesExistingEntries() throws {
        let library = library()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        library.recordVisit(title: "Private", url: url, isPrivate: true)
        XCTAssertTrue(library.snapshot.history.isEmpty)
        library.recordVisit(title: "First", url: url, isPrivate: false)
        library.recordVisit(title: "Second", url: url, isPrivate: false)
        XCTAssertEqual(library.snapshot.history.count, 1)
        XCTAssertEqual(library.snapshot.history.first?.title, "Second")
        var settings = library.settings
        settings.historyRetentionDays = 0
        library.updateSettings(settings)
        library.recordVisit(title: "Disabled", url: url, isPrivate: false)
        XCTAssertTrue(library.snapshot.history.isEmpty)
    }

    func testPermissionsAreExactOriginAndPersistLocally() throws {
        let library = library()
        library.setPermissions(SitePermissions(controls: .allow, scanner: .deny), for: "https://example.com")
        let reloaded = BrowserLibrary(fileURL: try XCTUnwrap(directory).appendingPathComponent("test.json"))
        XCTAssertEqual(reloaded.snapshot.permissions["https://example.com"]?.controls, .allow)
        XCTAssertNil(reloaded.snapshot.permissions["https://example.com:8443"])
        XCTAssertNil(reloaded.snapshot.permissions["https://other.example.com"])
    }

    func testOriginCanonicalization() throws {
        XCTAssertEqual(DuoOrigin.canonical(URL(string: "https://EXAMPLE.com:443/a")), "https://example.com")
        XCTAssertEqual(DuoOrigin.canonical(URL(string: "https://example.com:8443/b")), "https://example.com:8443")
        XCTAssertNil(DuoOrigin.canonical(URL(string: "http://example.com")))
        XCTAssertNil(DuoOrigin.canonical(URL(string: "file:///private/test.html")))
    }

    func testRateLimitAndSlidingWindow() {
        var limiter = DuoRateLimiter(maximumMessages: 2, interval: 10)
        XCTAssertTrue(limiter.accept(now: 0))
        XCTAssertTrue(limiter.accept(now: 1))
        XCTAssertFalse(limiter.accept(now: 2))
        XCTAssertTrue(limiter.accept(now: 10))
        XCTAssertFalse(limiter.accept(now: 10.5))
        XCTAssertTrue(limiter.accept(now: 11))
    }
}
