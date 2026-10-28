import Combine
import Foundation
import WebKit

struct RecentlyClosedTab: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let requestsDesktopSite: Bool
    let pageZoom: Double
    let closedAt = Date.now
}

@MainActor
final class BrowserTabManager: ObservableObject {
    @Published private(set) var tabs: [BrowserViewModel] = []
    @Published private(set) var selectedID: UUID?
    @Published var notice: String?
    @Published private(set) var isClearingData = false
    @Published private(set) var recentlyClosedTabs: [RecentlyClosedTab] = []
    let library: BrowserLibrary
    let downloads: DownloadManager
    private var privateDataStore = WKWebsiteDataStore.nonPersistent()
    private let removeWebsiteData: @MainActor () async -> Void
    private var isClosingMultipleTabs = false

    var selectedTab: BrowserViewModel? {
        tabs.first { $0.id == selectedID }
    }

    init(
        library: BrowserLibrary,
        removeWebsiteData: @escaping @MainActor () async -> Void = {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
            )
        }
    ) {
        self.library = library
        self.removeWebsiteData = removeWebsiteData
        downloads = DownloadManager(library: library)
        let session = library.snapshot.session
        if library.settings.restoreTabs, !session.tabs.isEmpty {
            for entry in session.tabs.prefix(library.settings.maximumTabs) {
                addTab(url: entry.url, desktop: entry.requestsDesktopSite,
                       pageZoom: entry.pageZoom, persist: false)
            }
            if tabs.indices.contains(session.selectedIndex) {
                selectedID = tabs[session.selectedIndex].id
            }
        }
        if tabs.isEmpty { addTab(persist: false) }
        for tab in tabs { tab.isActive = tab.id == selectedID }
        library.pruneHistory()
        saveSession()
    }

    @discardableResult
    func addTab(
        url: URL? = nil,
        isPrivate: Bool = false,
        desktop: Bool = false,
        pageZoom: Double = 1,
        persist: Bool = true,
        opensStartPage: Bool = true
    ) -> BrowserViewModel? {
        guard !isClearingData else {
            notice = "Wait until browsing data has finished clearing before opening a tab."
            return nil
        }
        guard tabs.count < library.settings.maximumTabs else {
            notice = "The tab limit has been reached. Close a tab or increase the limit in Settings."
            return nil
        }
        selectedTab?.deactivate()
        let tab = BrowserViewModel(
            library: library, downloads: downloads, isPrivate: isPrivate,
            dataStore: isPrivate ? privateDataStore : .default(),
            requestsDesktopSite: desktop, initialURL: url, opensStartPage: opensStartPage,
            pageZoom: pageZoom
        )
        tab.onNewWindow = { [weak self, weak tab] request in
            guard let self, let tab,
                  let created = self.addTab(isPrivate: tab.isPrivate, opensStartPage: false) else { return }
            created.loadRequest(request)
        }
        tab.onStateChanged = { [weak self] in self?.saveSession() }
        tabs.append(tab)
        selectedID = tab.id
        if persist { saveSession() }
        return tab
    }

    func select(_ id: UUID) {
        guard !isClearingData else { return }
        guard tabs.contains(where: { $0.id == id }), selectedID != id else { return }
        selectedTab?.deactivate()
        selectedID = id
        selectedTab?.isActive = true
        saveSession()
    }

    func close(_ id: UUID) {
        guard !isClearingData else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedID == id
        let wasPrivate = tabs[index].isPrivate
        let closedTab = tabs[index]
        if !wasPrivate, !closedTab.showingStartPage, let url = closedTab.restorableURL {
            recentlyClosedTabs.insert(RecentlyClosedTab(
                title: closedTab.pageTitle, url: url,
                requestsDesktopSite: closedTab.requestsDesktopSite, pageZoom: closedTab.pageZoom
            ), at: 0)
            recentlyClosedTabs = Array(recentlyClosedTabs.prefix(library.settings.maximumTabs))
        }
        tabs[index].tearDown()
        tabs.remove(at: index)
        if wasPrivate, !tabs.contains(where: \.isPrivate) {
            privateDataStore = .nonPersistent()
        }
        if tabs.isEmpty {
            addTab(isPrivate: wasPrivate, persist: false)
        } else if wasSelected {
            selectedID = tabs[min(index, tabs.count - 1)].id
            selectedTab?.isActive = true
        }
        saveSession()
    }

    @discardableResult
    func reopen(_ id: UUID) -> BrowserViewModel? {
        guard let entry = recentlyClosedTabs.first(where: { $0.id == id }) else {
            notice = "This closed tab is no longer available."
            return nil
        }
        guard let tab = addTab(
            url: entry.url, desktop: entry.requestsDesktopSite, pageZoom: entry.pageZoom
        ) else { return nil }
        recentlyClosedTabs.removeAll { $0.id == id }
        return tab
    }

    func forgetClosedTab(_ id: UUID) {
        recentlyClosedTabs.removeAll { $0.id == id }
    }

    func closeAll(isPrivate: Bool) {
        guard !isClearingData, !isClosingMultipleTabs else { return }
        let identifiers = tabs.filter { $0.isPrivate == isPrivate }.map(\.id)
        guard !identifiers.isEmpty else { return }
        isClosingMultipleTabs = true
        defer {
            isClosingMultipleTabs = false
            saveSession()
        }
        for id in identifiers { close(id) }
    }

    func saveSession() {
        guard !isClosingMultipleTabs else { return }
        let normalTabs = tabs.filter { !$0.isPrivate }
        let selectedIndex = normalTabs.firstIndex { $0.id == selectedID } ?? 0
        library.saveSession(SavedSession(
            tabs: normalTabs.map {
                RestoredTab(
                    url: $0.showingStartPage ? nil : $0.restorableURL,
                    requestsDesktopSite: $0.requestsDesktopSite, pageZoom: $0.pageZoom
                )
            },
            selectedIndex: selectedIndex
        ))
    }

    func revokeSite(_ origin: String) {
        for tab in tabs { tab.bridge.revoke(origin: origin) }
    }

    func clearWebsiteData() async {
        guard !isClearingData else { return }
        isClearingData = true
        for tab in tabs { tab.tearDown() }
        tabs.removeAll()
        selectedID = nil
        recentlyClosedTabs.removeAll()
        // Persist the empty session before any asynchronous cleanup can be interrupted.
        saveSession()
        await downloads.cancelAll()
        privateDataStore = .nonPersistent()
        library.clearHistory()
        library.clearPermissions()
        await removeWebsiteData()
        isClearingData = false
        // Do not immediately repopulate cleared website data via a custom startup URL.
        addTab(opensStartPage: false)
        if let message = downloads.operationError {
            notice = message
            downloads.operationError = nil
        }
    }
}
