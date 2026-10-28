import Foundation

struct BrowserNavigationError: Identifiable {
    let id = UUID()
    let message: String
    let url: URL?
}

struct BrowserAlert: Identifiable {
    enum Content {
        case notice(String)
        case openExternal(URL)
    }

    let id = UUID()
    let content: Content
}

struct PageDialog: Identifiable {
    enum Kind {
        case alert
        case confirmation
        case prompt
    }

    let id = UUID()
    let kind: Kind
    let website: String
    let message: String
    let defaultText: String
}

struct SharedPage: Identifiable {
    let id = UUID()
    let url: URL
}
