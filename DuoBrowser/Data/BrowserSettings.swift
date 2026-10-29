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

enum ReaderTheme: String, Codable, CaseIterable {
    case paper, sepia, night
}

struct ReaderPreferences: Codable, Equatable {
    var fontSize = 19
    var theme: ReaderTheme = .paper

    private enum CodingKeys: String, CodingKey { case fontSize, theme }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try container.decode(Int.self, forKey: .fontSize)
        theme = try container.decode(ReaderTheme.self, forKey: .theme)
        guard (15...28).contains(fontSize) else {
            throw DecodingError.dataCorruptedError(forKey: .fontSize, in: container, debugDescription: "Reader font size must be 15–28 points.")
        }
    }
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
    var reader = ReaderPreferences()
}

extension BrowserSettings {
    private enum CodingKeys: String, CodingKey {
        case searchProvider, maximumTabs, restoreTabs, historyRetentionDays, startPageAddress
        case appearance, defaultDuoPermission, defaultScannerPermission, denyWebsiteMedia, reader
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchProvider = try container.decode(SearchProvider.self, forKey: .searchProvider)
        maximumTabs = try container.decode(Int.self, forKey: .maximumTabs)
        restoreTabs = try container.decode(Bool.self, forKey: .restoreTabs)
        historyRetentionDays = try container.decode(Int.self, forKey: .historyRetentionDays)
        startPageAddress = try container.decode(String.self, forKey: .startPageAddress)
        appearance = try container.decode(BrowserAppearance.self, forKey: .appearance)
        defaultDuoPermission = try container.decode(SitePermission.self, forKey: .defaultDuoPermission)
        defaultScannerPermission = try container.decode(SitePermission.self, forKey: .defaultScannerPermission)
        denyWebsiteMedia = try container.decode(Bool.self, forKey: .denyWebsiteMedia)
        reader = try container.decodeIfPresent(ReaderPreferences.self, forKey: .reader) ?? ReaderPreferences()
    }
}

struct SitePermissions: Codable, Equatable {
    var controls: SitePermission = .ask
    var scanner: SitePermission = .ask
}
