import Combine
import CryptoKit
import Foundation
import OSLog
import WebKit

struct SiteNavigationPreferences: Codable, Equatable {
    var enabled = true
    var pinned: [String] = []
    var hidden: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, pinned, hidden }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pinned = try values.decodeIfPresent([String].self, forKey: .pinned) ?? []
        hidden = try values.decodeIfPresent([String].self, forKey: .hidden) ?? []
        guard pinned.count <= 3, hidden.count <= 24,
              Set(pinned).count == pinned.count, Set(hidden).count == hidden.count,
              (pinned + hidden).allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) else {
            throw DecodingError.dataCorruptedError(forKey: .pinned, in: values, debugDescription: "Invalid site navigation preferences.")
        }
    }
}

struct SiteNavigationContext: Equatable, Sendable {
    let tabID: UUID
    let epoch: UUID
    let url: URL
    let origin: String
}

struct SiteNavigationLink: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let url: URL

    init(label: String, url: URL) {
        id = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        self.label = label
        self.url = url
    }

    var icon: String {
        switch label.lowercased() {
        case "home": "house"
        case "products", "shop", "catalog": "square.grid.2x2"
        case "help", "support", "contact": "questionmark.circle"
        case "docs", "documentation", "guides": "book.closed"
        case "account", "profile": "person.crop.circle"
        case "search": "magnifyingglass"
        default: "arrow.turn.up.right"
        }
    }
}

struct SiteNavigationSnapshot: Equatable, Sendable {
    let context: SiteNavigationContext
    let documentID: String
    let links: [SiteNavigationLink]

    private struct Raw: Decodable {
        struct Link: Decodable { let label: String; let href: String }
        let url: String
        let documentID: String
        let links: [Link]
    }

    init(data: Data, context: SiteNavigationContext) throws {
        guard data.count <= 32_768 else { throw SiteNavigationError.invalidData }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard URL(string: raw.url) == context.url, UUID(uuidString: raw.documentID) != nil,
              raw.links.count <= 12, DuoOrigin.canonical(context.url) == context.origin else {
            throw SiteNavigationError.invalidData
        }
        var seen = Set<URL>()
        var accepted: [SiteNavigationLink] = []
        for item in raw.links {
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.count <= 48, item.href.utf8.count <= 1024,
                  let url = URL(string: item.href), Self.allowed(url, label: label, context: context),
                  seen.insert(url).inserted else { continue }
            accepted.append(SiteNavigationLink(label: label, url: url))
        }
        self.context = context
        documentID = raw.documentID
        links = accepted
    }

    static func allowed(_ target: URL, label: String, context: SiteNavigationContext) -> Bool {
        guard target.user == nil, target.password == nil, DuoOrigin.canonical(target) == context.origin else { return false }
        if context.origin != "duo-demo", target.scheme?.lowercased() != "https" { return false }
        let text = (label + " " + target.path).lowercased()
        let unsafe = #"(^|[\s/_-])(logout|log-out|signout|sign-out|delete|remove|destroy|checkout|purchase|buy|unsubscribe|disconnect|revoke)($|[\s/?#_-])"#
        guard text.range(of: unsafe, options: .regularExpression) == nil else { return false }
        let excluded = Set(["action", "cmd", "command", "do", "delete", "logout", "signout", "submit", "token", "auth", "csrf", "session"])
        guard let components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.allSatisfy { !excluded.contains($0.name.lowercased()) } ?? true
    }

    func toolbarLinks(preferences: SiteNavigationPreferences) -> [SiteNavigationLink] {
        guard preferences.enabled else { return [] }
        let visible = links.filter { !preferences.hidden.contains($0.id) }
        let pins = preferences.pinned.compactMap { id in visible.first { $0.id == id } }
        return Array((pins + visible.filter { !preferences.pinned.contains($0.id) }).prefix(3))
    }
}

struct SiteNavigationAction: Sendable {
    let context: SiteNavigationContext
    let documentID: String
    let destination: URL
}

enum SiteNavigationError: LocalizedError {
    case invalidData, changedPage, unavailable, busy
    var errorDescription: String? {
        switch self {
        case .invalidData: "The website's navigation could not be read safely."
        case .changedPage: "The page or its navigation changed. Refresh Site Navigation before using this link."
        case .unavailable: "Site Navigation supports verified HTTPS pages and the bundled demo."
        case .busy: "Another site navigation request is still being verified."
        }
    }
}

@MainActor
final class SiteNavigationModel: ObservableObject {
    static let world = WKContentWorld.world(name: "DuoSiteNavigation")
    @Published private(set) var snapshot: SiteNavigationSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isOpening = false
    @Published private var settings: BrowserSettings
    @Published private var privatePreferences: [String: SiteNavigationPreferences] = [:]
    var contextProvider: (() -> SiteNavigationContext?)?
    var open: ((URL) -> Void)?
    var notify: ((String) -> Void)?
    private weak var webView: WKWebView?
    private let library: BrowserLibrary
    private let isPrivate: Bool
    private var active = true
    private var suppressed = false
    private var watching = false
    private var observation: AnyCancellable?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var operation = UUID()
    private var linkOperation = UUID()
    private var linkDeadline: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "SiteNavigation")

    init(library: BrowserLibrary, isPrivate: Bool) {
        self.library = library
        self.isPrivate = isPrivate
        settings = library.settings
        observation = library.$snapshot.map(\.settings).removeDuplicates().sink { [weak self] value in
            self?.settings = value
            self?.refresh()
        }
    }

    var origin: String? { contextProvider?()?.origin }
    var preferences: SiteNavigationPreferences {
        guard let origin else { return SiteNavigationPreferences() }
        return isPrivate ? (privatePreferences[origin] ?? SiteNavigationPreferences())
            : (settings.navigationProfiles[origin] ?? SiteNavigationPreferences())
    }
    var detectionEnabled: Bool { settings.automaticallyDetectNavigation && preferences.enabled }
    var visibleSnapshot: SiteNavigationSnapshot? {
        guard detectionEnabled, !suppressed, let snapshot, snapshot.context == contextProvider?() else { return nil }
        return snapshot
    }
    var toolbarLinks: [SiteNavigationLink] { visibleSnapshot?.toolbarLinks(preferences: preferences) ?? [] }

    static func script() throws -> String {
        guard let url = Bundle.main.url(forResource: "SiteNavigation", withExtension: "js") else { throw SiteNavigationError.unavailable }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func install(on webView: WKWebView) throws {
        self.webView = webView
        webView.configuration.userContentController.add(SiteNavigationProxy(owner: self), contentWorld: Self.world, name: "siteNavigation")
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: try Self.script(), injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world
        ))
    }

    private func call(_ arguments: [String: Any]) async throws -> Any? {
        guard let webView else { throw SiteNavigationError.unavailable }
        return try await webView.callAsyncJavaScript("return " + Self.script(), arguments: arguments, in: nil, contentWorld: Self.world)
    }

    func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === webView, active, !suppressed,
              detectionEnabled, contextProvider?() != nil,
              let webView, DuoOrigin.validated(message: message, webView: webView) != nil,
              let body = message.body as? [String: String], body.count == 2,
              UUID(uuidString: body["documentID"] ?? "") != nil,
              (body["url"]?.utf8.count ?? 0) <= 16_384,
              URL(string: body["url"] ?? "") == webView.url else {
            logger.debug("Ignored stale or inactive navigation observation.")
            return
        }
        refresh()
    }

    func setActive(_ value: Bool) {
        let wasActive = active
        active = value
        if value {
            if !wasActive, isRefreshing { cancel(clear: false) }
            refresh()
        } else { cancel(clear: false) }
    }

    func setSuppressed(_ value: Bool) {
        guard suppressed != value else { return }
        suppressed = value
        if value { cancel(clear: false) } else { refresh() }
        objectWillChange.send()
    }

    func reset() { cancel(clear: true) }

    private func cancel(clear: Bool) {
        operation = UUID()
        work?.cancel()
        deadline?.cancel()
        work = nil
        deadline = nil
        isRefreshing = false
        linkOperation = UUID()
        linkDeadline?.cancel()
        linkDeadline = nil
        isOpening = false
        if clear { snapshot = nil; errorMessage = nil }
        let shouldPause = watching
        watching = false
        guard shouldPause else { return }
        let view = webView
        Task { @MainActor [weak self, weak view] in
            guard let view else { return }
            if let self, self.watching { return }
            do {
                _ = try await view.callAsyncJavaScript(
                    "return " + Self.script(), arguments: ["mode": "pause"], in: nil, contentWorld: Self.world
                )
            } catch {
                Logger(subsystem: "com.duobrowser.app", category: "SiteNavigation").debug("Navigation observer pause failed: code \((error as NSError).code)")
            }
        }
    }

    func refresh(allowInactive: Bool = false) {
        guard active || allowInactive, !suppressed, detectionEnabled, let context = contextProvider?() else {
            cancel(clear: !detectionEnabled || contextProvider?() == nil)
            return
        }
        guard !isRefreshing else { return }
        errorMessage = nil
        isRefreshing = true
        let id = UUID()
        operation = id
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                if self.active {
                    self.watching = true
                    _ = try await self.call(["mode": "watch"])
                }
                let result = try await self.call(["mode": "capture", "allowDemo": context.origin == "duo-demo"])
                try Task.checkCancellation()
                guard self.operation == id, self.active || allowInactive, !self.suppressed, self.contextProvider?() == context else { return }
                guard let text = result as? String, let data = text.data(using: .utf8) else { throw SiteNavigationError.invalidData }
                let snapshot = try SiteNavigationSnapshot(data: data, context: context)
                self.deadline?.cancel()
                self.deadline = nil
                self.isRefreshing = false
                self.work = nil
                if self.snapshot != snapshot { self.snapshot = snapshot }
            } catch {
                guard self.operation == id else { return }
                self.deadline?.cancel()
                self.deadline = nil
                self.isRefreshing = false
                self.work = nil
                if !(error is CancellationError) {
                    self.snapshot = nil
                    self.logger.error("Site navigation detection failed: code \((error as NSError).code)")
                    self.errorMessage = "Site navigation could not be detected. The website is unchanged; use its own menu or refresh detection."
                }
            }
        }
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) }
            catch is CancellationError { return }
            catch {
                self?.logger.error("Site navigation deadline interrupted: code \((error as NSError).code)")
                return
            }
            guard let self, self.operation == id else { return }
            self.cancel(clear: true)
            self.errorMessage = "Site navigation detection timed out. Use the website's menu or try again."
            self.logger.error("Site navigation detection timed out.")
        }
    }

    func prepare(_ link: SiteNavigationLink) async throws -> SiteNavigationAction {
        guard !isOpening else { throw SiteNavigationError.busy }
        guard let snapshot, snapshot.context == contextProvider?(), snapshot.links.contains(link),
              detectionEnabled, !suppressed else { throw SiteNavigationError.changedPage }
        let id = UUID()
        linkOperation = id
        isOpening = true
        linkDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) }
            catch is CancellationError { return }
            catch {
                self?.logger.error("Link validation deadline interrupted: code \((error as NSError).code)")
                return
            }
            guard let self, self.linkOperation == id else { return }
            self.linkOperation = UUID()
            self.isOpening = false
            self.errorMessage = "The navigation check timed out. Nothing was opened."
            self.logger.error("Site navigation link validation timed out.")
        }
        defer {
            if linkOperation == id {
                isOpening = false
                linkDeadline?.cancel()
                linkDeadline = nil
            }
        }
        let valid = try await call([
            "mode": "validate", "allowDemo": snapshot.context.origin == "duo-demo",
            "sourceURL": snapshot.context.url.absoluteString, "documentID": snapshot.documentID, "href": link.url.absoluteString
        ])
        guard linkOperation == id, valid as? Bool == true, snapshot.context == contextProvider?() else { throw SiteNavigationError.changedPage }
        return SiteNavigationAction(context: snapshot.context, documentID: snapshot.documentID, destination: link.url)
    }

    func isCurrent(_ action: SiteNavigationAction) -> Bool {
        action.context == contextProvider?() && snapshot?.documentID == action.documentID
            && detectionEnabled && !suppressed
    }

    func activate(_ link: SiteNavigationLink) {
        guard active else {
            errorMessage = "Return to the page before using its navigation."
            notify?("Return to the page before using its navigation.")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let action = try await self.prepare(link)
                guard self.active, self.isCurrent(action) else { throw SiteNavigationError.changedPage }
                guard let open = self.open else { throw SiteNavigationError.unavailable }
                open(action.destination)
            } catch {
                self.showValidationError(error)
                if let message = self.errorMessage { self.notify?(message) }
            }
        }
    }

    func updatePreferences(_ update: (inout SiteNavigationPreferences) -> Void) {
        guard let origin else { errorMessage = SiteNavigationError.unavailable.localizedDescription; return }
        var profile = preferences
        update(&profile)
        guard profile.pinned.count <= 3, profile.hidden.count <= 24 else {
            errorMessage = "Keep at most three pinned links and 24 hidden links per site. Reset this site's choices to clear old entries."
            return
        }
        if isPrivate {
            if profile == SiteNavigationPreferences() { privatePreferences.removeValue(forKey: origin) }
            else { privatePreferences[origin] = profile }
        }
        else {
            var settings = library.settings
            if profile == SiteNavigationPreferences() { settings.navigationProfiles.removeValue(forKey: origin) }
            else { settings.navigationProfiles[origin] = profile }
            guard library.updateSettings(settings) else { errorMessage = "Site navigation preferences could not be saved."; return }
        }

        if profile.enabled { refresh(allowInactive: true) } else { cancel(clear: true) }
    }

    func showValidationError(_ error: Error) {
        logger.error("Detected link validation failed: code \((error as NSError).code)")
        errorMessage = (error as? SiteNavigationError)?.localizedDescription ?? "The detected link could not be verified. Refresh Site Navigation."
    }

    func refreshForReview() {
        guard detectionEnabled, !suppressed, contextProvider?() != nil else {
            errorMessage = "Enable automatic navigation and this site's shortcuts first. Website-provided DuoKit controls take priority."
            return
        }
        refresh(allowInactive: true)
    }

    func tearDown() {
        cancel(clear: true)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "siteNavigation", contentWorld: Self.world)
        observation = nil
        contextProvider = nil
        open = nil
        notify = nil
        webView = nil
    }
}

@MainActor
private final class SiteNavigationProxy: NSObject, WKScriptMessageHandler {
    weak var owner: SiteNavigationModel?
    init(owner: SiteNavigationModel) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}
