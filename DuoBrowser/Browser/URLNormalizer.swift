import Foundation

enum SearchProvider: String, CaseIterable, Codable {
    case duckDuckGo
    case google
    case bing

    func searchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        switch self {
        case .duckDuckGo:
            components.host = "duckduckgo.com"
            components.path = "/"
        case .google:
            components.host = "www.google.com"
            components.path = "/search"
        case .bing:
            components.host = "www.bing.com"
            components.path = "/search"
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

enum NavigationTarget: Equatable {
    case empty
    case website(URL)
    case search(URL)
    case external(URL)
    case invalid(String)
}

enum URLNormalizer {
    static let externalSchemes: Set<String> = [
        "mailto", "tel", "sms", "facetime", "facetime-audio", "maps", "itms-apps"
    ]

    static func resolve(
        _ input: String,
        searchProvider: SearchProvider = .duckDuckGo
    ) -> NavigationTarget {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }

        if let url = webURL(from: value) {
            return .website(url)
        }

        let scheme = URLComponents(string: value)?.scheme?.lowercased()
        if let scheme, externalSchemes.contains(scheme),
           let url = URL(string: value), value.count > scheme.count + 1 {
            return .external(url)
        }

        let blockedSchemes: Set<String> = [
            "http", "https", "javascript", "data", "file", "about", "blob"
        ]
        if value.contains("://") || scheme.map({ blockedSchemes.contains($0) }) == true {
            return .invalid("Enter a valid website address or a search phrase.")
        }

        guard let url = searchProvider.searchURL(for: value) else {
            return .invalid("This search could not be prepared. Try a different phrase.")
        }
        return .search(url)
    }

    static func webURL(from input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let hasWebScheme = value.lowercased().hasPrefix("https://")
            || value.lowercased().hasPrefix("http://")
        guard let components = URLComponents(
            string: hasWebScheme ? value : "https://\(value)"
        ),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              components.user == nil,
              components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true
        else { return nil }

        if !hasWebScheme {
            guard !value.contains(where: { $0.isWhitespace }),
                  host.contains(".") || host == "localhost" || host.contains(":")
            else { return nil }
        }
        return components.url
    }
}
