import Foundation

enum SitePermission: String, Codable, CaseIterable {
    case ask
    case allow
    case deny
}

enum BrowserAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

struct BrowserSettings: Codable, Equatable {
    var searchProvider: SearchProvider = .duckDuckGo
    var maximumTabs = 20
    var restoreTabs = true
    var historyRetentionDays = 30
    var startPageAddress = ""
    var appearance: BrowserAppearance = .system
    var defaultDuoPermission: SitePermission = .ask
    var defaultScannerPermission: SitePermission = .ask
    var denyWebsiteMedia = false
}

struct SitePermissions: Codable, Equatable {
    var controls: SitePermission = .ask
    var scanner: SitePermission = .ask
}
