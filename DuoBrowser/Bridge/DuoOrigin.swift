import Foundation
import WebKit

enum DuoOrigin {
    static var demoURL: URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Demo")
    }

    static func canonical(_ url: URL?) -> String? {
        guard let url else { return nil }
        if let demoURL, url.deletingFragment == demoURL { return "duo-demo" }
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        let port = url.port ?? 443
        return "https://\(host)\(port == 443 ? "" : ":\(port)")"
    }

    static func validated(message: WKScriptMessage, webView: WKWebView) -> String? {
        guard message.frameInfo.isMainFrame,
              let current = canonical(webView.url),
              canonical(message.frameInfo.request.url) == current else { return nil }
        if current == "duo-demo" { return current }
        let origin = message.frameInfo.securityOrigin
        guard origin.protocol.lowercased() == "https",
              let host = webView.url?.host?.lowercased(),
              origin.host.lowercased() == host,
              (origin.port == 0 ? 443 : origin.port) == (webView.url?.port ?? 443) else { return nil }
        return current
    }
}

private extension URL {
    var deletingFragment: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}
