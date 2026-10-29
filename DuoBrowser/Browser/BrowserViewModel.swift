import Combine
import OSLog
import UIKit
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    let id = UUID()
    let isPrivate: Bool
    let library: BrowserLibrary
    let downloads: DownloadManager
    let bridge: DuoBridge
    var onNewWindow: ((URLRequest) -> Void)?
    var onStateChanged: (() -> Void)?
    var isActive: Bool {
        get { !isClosed && !isEditingAddress && !isShowingAssistant && bridge.isActive }
        set { bridge.isActive = newValue && !isClosed && !isEditingAddress && !isShowingAssistant }
    }
    @Published private(set) var navigationID = UUID()
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle = ""
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hasOnlySecureContent = false
    @Published private(set) var pageBackgroundColor = UIColor.systemBackground
    @Published private(set) var showingStartPage = true
    @Published private(set) var requestsDesktopSite: Bool
    @Published private(set) var pageZoom = 1.0
    @Published private(set) var navigationError: BrowserNavigationError?
    @Published var alert: BrowserAlert?
    @Published var pageDialog: PageDialog?
    private(set) var isClosed = false
    private(set) var isEditingAddress = false
    private(set) var isShowingAssistant = false

    let webView: WKWebView
    private let webDelegate: BrowserWebDelegate
    private var bridgeObservation: AnyCancellable?
    private var observations: [NSKeyValueObservation] = []
    private var requestedURL: URL?
    private var dialogCompletion: ((String?) -> Void)?
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "Navigation")

    var addressText: String {
        if showingStartPage { return "" }
        return (navigationError?.url ?? currentURL ?? requestedURL)?.absoluteString ?? ""
    }

    var isSecure: Bool {
        !showingStartPage && navigationError == nil
            && currentURL?.scheme?.lowercased() == "https" && hasOnlySecureContent
    }

    var browserBackgroundColor: UIColor {
        if showingStartPage { return .systemGroupedBackground }
        if navigationError != nil { return .systemBackground }
        return pageBackgroundColor
    }

    var shareURL: URL? {
        guard !showingStartPage, navigationError == nil,
              let url = currentURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    var restorableURL: URL? {
        let candidate = navigationError?.url ?? currentURL ?? requestedURL
        guard let candidate, ["http", "https"].contains(candidate.scheme?.lowercased() ?? "") else {
            return nil
        }
        return candidate
    }

    init(
        library: BrowserLibrary,
        downloads: DownloadManager,
        isPrivate: Bool,
        dataStore: WKWebsiteDataStore,
        requestsDesktopSite: Bool = false,
        initialURL: URL? = nil,
        opensStartPage: Bool = true,
        pageZoom: Double = 1
    ) {
        self.library = library
        self.downloads = downloads
        self.isPrivate = isPrivate
        self.requestsDesktopSite = requestsDesktopSite
        bridge = DuoBridge(library: library, isPrivate: isPrivate)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.preferredContentMode = requestsDesktopSite ? .desktop : .mobile
        webView = WKWebView(frame: .zero, configuration: configuration)
        webDelegate = BrowserWebDelegate()
        webDelegate.owner = self
        bridge.canPresentNativeUI = { [weak self] in
            guard let self else { return false }
            return !self.isEditingAddress && !self.isShowingAssistant && self.pageDialog == nil && self.alert == nil
        }
        webView.navigationDelegate = webDelegate
        webView.uiDelegate = webDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.isFindInteractionEnabled = true
        webView.scrollView.keyboardDismissMode = .interactive

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(
            webDelegate, action: #selector(BrowserWebDelegate.refreshPage), for: .valueChanged
        )
        webView.scrollView.refreshControl = refreshControl
        do {
            try bridge.install(on: webView)
        } catch {
            showNotice("DuoKit could not be loaded. Normal browsing remains available. \(error.localizedDescription)")
        }
        bridgeObservation = bridge.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        setPageZoom(pageZoom)
        observeWebView()
        if let initialURL { load(initialURL) }
        else if opensStartPage { goToStartPage() }
    }

    func beginAddressEditing() {
        guard !isClosed else { return }
        isEditingAddress = true
        deactivate()
    }

    func endAddressEditing(isActive: Bool) {
        isEditingAddress = false
        self.isActive = isActive
    }

    func beginAssistantPresentation() {
        guard !isClosed else { return }
        isShowingAssistant = true
        deactivate()
    }

    func endAssistantPresentation(isActive: Bool) {
        isShowingAssistant = false
        self.isActive = isActive
    }

    func navigate(_ input: String) {
        switch URLNormalizer.resolve(input, searchProvider: library.settings.searchProvider) {
        case .empty:
            break
        case .website(let url), .search(let url):
            load(url)
        case .external(let url):
            requestExternalNavigation(url)
        case .invalid(let message):
            showNotice(message)
        }
    }

    func load(_ url: URL) {
        guard !isClosed else { return }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            showNotice("Duo Browser can only load HTTP and HTTPS webpages.")
            return
        }
        navigationID = UUID()
        cancelPageDialog()
        requestedURL = url
        navigationError = nil
        showingStartPage = false
        webView.load(URLRequest(url: url))
        onStateChanged?()
    }

    func goToStartPage() {
        guard !isClosed else { return }
        navigationID = UUID()
        cancelPageDialog()
        bridge.navigationStarted()
        webView.stopLoading()
        webView.pauseAllMediaPlayback()
        let value = library.settings.startPageAddress
        if !value.isEmpty {
            guard let url = URLNormalizer.webURL(from: value) else {
                showingStartPage = true
                navigationError = nil
                showNotice("Your saved start page is not a valid website address. Update it in Start Page settings.")
                return
            }
            load(url)
        } else {
            showingStartPage = true
            navigationError = nil
            webView.scrollView.refreshControl?.endRefreshing()
        }
        onStateChanged?()
    }

    func loadRequest(_ request: URLRequest) {
        guard !isClosed else { return }
        guard let url = request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            showNotice("The new window did not request a supported website.")
            return
        }
        navigationID = UUID()
        showingStartPage = false
        navigationError = nil
        requestedURL = url
        webView.load(request)
        onStateChanged?()
    }

    func loadDemo() {
        guard !isClosed else { return }
        guard let url = DuoOrigin.demoURL else {
            showNotice("The DuoKit demo is missing from this build.")
            return
        }
        navigationID = UUID()
        showingStartPage = false
        navigationError = nil
        requestedURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        onStateChanged?()
    }

    func goBack() {
        guard !isClosed else { return }
        navigationID = UUID()
        if showingStartPage, currentURL != nil {
            showingStartPage = false
            onStateChanged?()
        } else {
            webView.goBack()
        }
    }

    func goForward() {
        guard !isClosed else { return }
        navigationID = UUID()
        showingStartPage = false
        webView.goForward()
    }

    func reload() {
        guard !isClosed else { return }
        navigationID = UUID()
        if let navigationError, let url = navigationError.url {
            load(url)
        } else if !showingStartPage {
            webView.reload()
        } else {
            webView.scrollView.refreshControl?.endRefreshing()
        }
    }

    func stop() {
        guard !isClosed else { return }
        navigationID = UUID()
        webView.stopLoading()
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func toggleContentMode() {
        guard !isClosed else { return }
        navigationID = UUID()
        requestsDesktopSite.toggle()
        webView.configuration.defaultWebpagePreferences.preferredContentMode =
            requestsDesktopSite ? .desktop : .mobile
        if !showingStartPage {
            navigationError = nil
            webView.reloadFromOrigin()
        }
        onStateChanged?()
    }

    func findInPage() {
        guard !isClosed, !showingStartPage, navigationError == nil else { return }
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    func setPageZoom(_ value: Double) {
        guard !isClosed else { return }
        guard value.isFinite, (0.5...3).contains(value) else {
            showNotice("Page zoom must be between 50% and 300%.")
            return
        }
        pageZoom = value
        webView.pageZoom = CGFloat(value)
        onStateChanged?()
    }

    func showNotice(_ message: String) {
        alert = BrowserAlert(content: .notice(message))
    }

    func requestExternalNavigation(_ url: URL) {
        guard !isClosed else { return }
        guard URLNormalizer.externalSchemes.contains(url.scheme?.lowercased() ?? "") else {
            showNotice("This type of link is not supported.")
            return
        }
        alert = BrowserAlert(content: .openExternal(url))
    }

    func openExternal(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self, !self.isClosed else { return }
            let opened = await UIApplication.shared.open(url, options: [:])
            if !opened {
                self.showNotice("No installed app could open this link.")
            }
        }
    }

    func navigationWillStart() {
        guard !isClosed else { return }
        navigationID = UUID()
        cancelPageDialog()
        bridge.navigationStarted()
        navigationError = nil
        showingStartPage = false
    }

    func rememberRequest(_ url: URL?) {
        guard !isClosed else { return }
        requestedURL = url
    }

    func navigationDidFinish() {
        guard !isClosed else { return }
        navigationError = nil
        synchronizeState()
        webView.scrollView.refreshControl?.endRefreshing()
        if let url = currentURL {
            library.recordVisit(title: pageTitle, url: url, isPrivate: isPrivate)
        }
        onStateChanged?()
    }

    func navigationDidFail(_ error: Error) {
        guard !isClosed else { return }
        webView.scrollView.refreshControl?.endRefreshing()
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else {
            return
        }
        // Do not log addresses, page content, or other browsing data.
        logger.error("Navigation failed: code \(error.code)")
        let message: String
        if error.domain == NSURLErrorDomain, (-1206 ... -1200).contains(error.code) {
            message = "A secure connection could not be established. Duo Browser does not bypass certificate checks."
        } else if error.domain == NSURLErrorDomain, error.code == NSURLErrorNotConnectedToInternet {
            message = "You appear to be offline. Check your internet connection and try again."
        } else {
            message = "This page could not be loaded. Check the address and your connection, then try again."
        }
        let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        navigationError = BrowserNavigationError(
            message: message, url: failingURL ?? requestedURL ?? currentURL
        )
        synchronizeState()
    }

    func contentProcessDidTerminate() {
        guard !isClosed else { return }
        navigationID = UUID()
        cancelPageDialog()
        bridge.navigationStarted()
        webView.scrollView.refreshControl?.endRefreshing()
        navigationError = BrowserNavigationError(
            message: "The webpage stopped responding. Reload it to continue.",
            url: currentURL ?? requestedURL
        )
        synchronizeState()
    }

    func presentPageDialog(
        kind: PageDialog.Kind,
        website: String,
        message: String,
        defaultText: String = "",
        completion: @escaping (String?) -> Void
    ) {
        guard !isClosed, pageDialog == nil, !showingStartPage, isActive,
              bridge.permissionRequest == nil, bridge.scannerRequest == nil else {
            completion(nil)
            return
        }
        dialogCompletion = completion
        pageDialog = PageDialog(
            kind: kind, website: website, message: message, defaultText: defaultText
        )
    }

    func completePageDialog(with value: String?) {
        let completion = dialogCompletion
        dialogCompletion = nil
        pageDialog = nil
        completion?(value)
    }

    func cancelPageDialog() {
        completePageDialog(with: nil)
    }

    func deactivate() {
        bridge.deactivate()
        cancelPageDialog()
        webView.pauseAllMediaPlayback()
    }

    func tearDown() {
        guard !isClosed else { return }
        isClosed = true
        navigationID = UUID()
        deactivate()
        bridge.tearDown()
        observations.removeAll()
        bridgeObservation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onNewWindow = nil
        onStateChanged = nil
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            webView.observe(\.underPageBackgroundColor, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            }
        ]
    }

    private func synchronizeState() {
        guard !isClosed else { return }
        currentURL = webView.url
        pageTitle = webView.title ?? ""
        isLoading = webView.isLoading
        estimatedProgress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        hasOnlySecureContent = webView.hasOnlySecureContent
        pageBackgroundColor = webView.underPageBackgroundColor ?? .systemBackground
        if !isLoading {
            webView.scrollView.refreshControl?.endRefreshing()
        }
    }
}
