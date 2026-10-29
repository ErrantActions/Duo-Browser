import Foundation
import WebKit

enum AskDuoError: LocalizedError {
    case unavailable(String)
    case invalidContext
    case staleContext
    case invalidAnswer
    case invalidLink
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .invalidContext: return "A readable, bounded page excerpt could not be captured. No page data was sent to a model."
        case .staleContext: return "The page changed. Read it again before asking or opening a link."
        case .invalidAnswer: return "Apple Intelligence returned an invalid answer or an unapproved action. Nothing was opened."
        case .invalidLink: return "That link is not an eligible link in the reviewed page. Nothing was opened."
        case .timedOut: return "Ask Duo timed out. Nothing was opened. Try again with a shorter question."
        }
    }
}

struct AskDuoLink: Identifiable, Equatable, Sendable {
    let id: Int
    let label: String
    let url: URL
}

struct AskDuoAnswer: Equatable, Sendable {
    let text: String
    let link: AskDuoLink?
}

struct AskDuoNavigation: Sendable {
    let tabID: UUID
    let navigationID: UUID
    let sourceURL: URL
    let destination: URL

    @MainActor
    func isCurrent(for model: BrowserViewModel) -> Bool {
        destination.scheme?.lowercased() == "https" && destination.user == nil && destination.password == nil
            && tabID == model.id && navigationID == model.navigationID
            && sourceURL == model.webView.url && AskDuoPageReader.blockedReason(for: model) == nil
    }
}

struct AskDuoContext: Sendable {
    let tabID: UUID
    let navigationID: UUID
    let url: URL
    let sourceAddress: String
    let documentID: String
    let title: String
    let text: String
    let truncated: Bool
    let links: [AskDuoLink]

    private struct Raw: Decodable {
        struct Link: Decodable { let label: String; let href: String }
        let url: String
        let documentID: String
        let title: String
        let text: String
        let truncated: Bool
        let links: [Link]
    }

    init(data: Data, tabID: UUID, navigationID: UUID, sourceURL: URL) throws {
        guard data.count <= 32_768 else { throw AskDuoError.invalidContext }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard URL(string: raw.url) == sourceURL, UUID(uuidString: raw.documentID) != nil,
              raw.links.count <= 12, DuoOrigin.canonical(sourceURL) != nil else {
            throw AskDuoError.invalidContext
        }
        self.tabID = tabID
        self.navigationID = navigationID
        url = sourceURL
        sourceAddress = raw.url
        documentID = raw.documentID
        title = String(raw.title.prefix(80))
        text = String(raw.text.prefix(1800))
        truncated = raw.truncated || raw.text.count > 1800
        var seen = Set<URL>()
        var valid: [AskDuoLink] = []
        for item in raw.links {
            guard item.href.count <= 1024,
                  let target = URLNormalizer.webURL(from: item.href),
                  target.scheme?.lowercased() == "https",
                  seen.insert(target).inserted else { continue }
            let label = String(item.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            valid.append(AskDuoLink(id: valid.count + 1, label: label.isEmpty ? (target.host ?? "Link") : label, url: target))
        }
        links = valid
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !links.isEmpty else {
            throw AskDuoError.invalidContext
        }
    }

    func answer(text: String, linkID: Int, allowsNavigation: Bool) throws -> AskDuoAnswer {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000,
              linkID >= 0, linkID <= links.count, allowsNavigation || linkID == 0 else {
            throw AskDuoError.invalidAnswer
        }
        return AskDuoAnswer(text: text, link: linkID == 0 ? nil : links[linkID - 1])
    }

    func promptData() throws -> String {
        struct PromptLink: Encodable { let id: Int; let label: String }
        struct Page: Encodable {
            let host: String
            let title: String
            let excerpt: String
            let links: [PromptLink]
        }
        let data = try JSONEncoder().encode(Page(
            host: DuoOrigin.canonical(url) ?? "Page", title: title, excerpt: text,
            links: links.map { PromptLink(id: $0.id, label: $0.label) }
        ))
        guard let result = String(data: data, encoding: .utf8) else { throw AskDuoError.invalidContext }
        return result
    }

    @MainActor
    func isCurrent(for model: BrowserViewModel) -> Bool {
        tabID == model.id && navigationID == model.navigationID && url == model.webView.url
            && AskDuoPageReader.blockedReason(for: model) == nil
    }
}

@MainActor
enum AskDuoPageReader {
    private static let world = WKContentWorld.world(name: "AskDuo")

    static func blockedReason(for model: BrowserViewModel) -> String? {
        if model.isPrivate { return "Ask Duo is disabled in Private Browsing. No page will be read." }
        if model.isClosed { return "This tab is closed." }
        if model.showingStartPage { return "Open an HTTPS webpage or the DuoKit demo first." }
        if model.navigationError != nil { return "Resolve the page error before using Ask Duo." }
        if model.webView.isLoading { return "Wait for the page to finish loading." }
        guard let origin = DuoOrigin.canonical(model.webView.url),
              origin == "duo-demo" || model.isSecure else {
            return "Ask Duo reads only verified HTTPS pages and the bundled DuoKit demo."
        }
        return nil
    }

    private static func script() throws -> String {
        guard let url = Bundle.main.url(forResource: "AskDuoContext", withExtension: "js") else {
            throw AskDuoError.unavailable("The Ask Duo context reader is missing from this build.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func read(from model: BrowserViewModel) async throws -> AskDuoContext {
        if let reason = blockedReason(for: model) { throw AskDuoError.unavailable(reason) }
        guard let source = model.webView.url else { throw AskDuoError.invalidContext }
        let generation = model.navigationID
        let value = try await model.webView.callAsyncJavaScript(
            script(), arguments: ["mode": "capture"], in: nil, contentWorld: world
        )
        guard let raw = value as? String, let data = raw.data(using: .utf8) else { throw AskDuoError.invalidContext }
        let context = try AskDuoContext(data: data, tabID: model.id, navigationID: generation, sourceURL: source)
        guard context.isCurrent(for: model) else { throw AskDuoError.staleContext }
        return context
    }

    static func navigation(for link: AskDuoLink, context: AskDuoContext, model: BrowserViewModel) async throws -> AskDuoNavigation {
        guard context.isCurrent(for: model) else { throw AskDuoError.staleContext }
        guard context.links.contains(link) else { throw AskDuoError.invalidLink }
        let value = try await model.webView.callAsyncJavaScript(
            script(), arguments: [
                "mode": "validate", "sourceURL": context.sourceAddress,
                "documentID": context.documentID, "href": link.url.absoluteString
            ], in: nil, contentWorld: world
        )
        guard value as? Bool == true, context.isCurrent(for: model) else { throw AskDuoError.staleContext }
        return AskDuoNavigation(
            tabID: model.id, navigationID: model.navigationID,
            sourceURL: context.url, destination: link.url
        )
    }
}
