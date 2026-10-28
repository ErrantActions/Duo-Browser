import Combine
import Foundation
import OSLog

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: URL
    var folder: String
    var isFavorite: Bool

    var displayTitle: String {
        title.isEmpty ? (url.host() ?? url.absoluteString) : title
    }

    init(id: UUID = UUID(), title: String, url: URL, folder: String = "", isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, folder, isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        // Existing bookmarks predate favorites and must remain readable.
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || "\(title) \(url.absoluteString) \(folder)".localizedCaseInsensitiveContains(query)
    }
}

enum BookmarkCollection: Hashable {
    case all
    case favorites
    case unfiled
    case folder(String)

    func contains(_ bookmark: Bookmark) -> Bool {
        switch self {
        case .all: true
        case .favorites: bookmark.isFavorite
        case .unfiled: bookmark.folder.isEmpty
        case .folder(let name): bookmark.folder == name
        }
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: URL
    var lastVisited: Date
}

struct HistoryDay: Identifiable {
    let date: Date
    let entries: [HistoryEntry]
    var id: Date { date }

    static func grouped(
        _ history: [HistoryEntry], matching query: String, calendar: Calendar = .current
    ) -> [HistoryDay] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = history.filter {
            query.isEmpty || "\($0.title) \($0.url.absoluteString)".localizedCaseInsensitiveContains(query)
        }
        return Dictionary(grouping: matching, by: { calendar.startOfDay(for: $0.lastVisited) })
            .map { date, entries in
                HistoryDay(date: date, entries: entries.sorted {
                    if $0.lastVisited == $1.lastVisited { return $0.url.absoluteString < $1.url.absoluteString }
                    return $0.lastVisited > $1.lastVisited
                })
            }
            .sorted { $0.date > $1.date }
    }
}

struct RestoredTab: Codable {
    var url: URL?
    var requestsDesktopSite: Bool
    var pageZoom: Double

    init(url: URL?, requestsDesktopSite: Bool, pageZoom: Double = 1) {
        self.url = url
        self.requestsDesktopSite = requestsDesktopSite
        self.pageZoom = pageZoom
    }

    private enum CodingKeys: String, CodingKey {
        case url, requestsDesktopSite, pageZoom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        requestsDesktopSite = try container.decode(Bool.self, forKey: .requestsDesktopSite)
        pageZoom = try container.decodeIfPresent(Double.self, forKey: .pageZoom) ?? 1
        guard pageZoom.isFinite, (0.5...3).contains(pageZoom) else {
            throw DecodingError.dataCorruptedError(
                forKey: .pageZoom, in: container, debugDescription: "Page zoom must be between 0.5 and 3."
            )
        }
    }
}

struct SavedSession: Codable {
    var tabs: [RestoredTab] = []
    var selectedIndex = 0
}

struct LibrarySnapshot: Codable {
    var settings = BrowserSettings()
    var bookmarks: [Bookmark] = []
    var history: [HistoryEntry] = []
    var permissions: [String: SitePermissions] = [:]
    var session = SavedSession()
    var downloads: [DownloadItem] = []
    var readingList: [ReadingListItem] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case settings, bookmarks, history, permissions, session, downloads, readingList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decode(BrowserSettings.self, forKey: .settings)
        bookmarks = try container.decode([Bookmark].self, forKey: .bookmarks)
        history = try container.decode([HistoryEntry].self, forKey: .history)
        permissions = try container.decode([String: SitePermissions].self, forKey: .permissions)
        session = try container.decode(SavedSession.self, forKey: .session)
        downloads = try container.decode([DownloadItem].self, forKey: .downloads)
        readingList = try container.decodeIfPresent([ReadingListItem].self, forKey: .readingList) ?? []
    }
}

@MainActor
final class BrowserLibrary: ObservableObject {
    @Published private(set) var snapshot: LibrarySnapshot
    @Published var storageError: String?
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "Storage")

    var settings: BrowserSettings { snapshot.settings }
    var favorites: [Bookmark] { snapshot.bookmarks.filter(\.isFavorite) }
    var bookmarkFolders: [String] {
        Array(Set(snapshot.bookmarks.map(\.folder).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("DuoBrowser", isDirectory: true)
            .appendingPathComponent("library.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                snapshot = try JSONDecoder().decode(
                    LibrarySnapshot.self, from: Data(contentsOf: self.fileURL)
                )
            } else {
                snapshot = LibrarySnapshot()
            }
        } catch {
            snapshot = LibrarySnapshot()
            storageError = "Saved browser data could not be read. Changes will not overwrite it. Check your device storage and restart Duo Browser."
            isReadOnly = true
            logger.error("Saved browser data could not be read.")
        }
    }

    private var isReadOnly = false

    func updateSettings(_ settings: BrowserSettings) {
        var settings = settings
        settings.maximumTabs = min(100, max(1, settings.maximumTabs))
        settings.historyRetentionDays = min(365, max(0, settings.historyRetentionDays))
        snapshot.settings = settings
        pruneHistory()
        if !settings.restoreTabs { snapshot.session = SavedSession() }
        save()
    }

    @discardableResult
    func saveBookmark(_ bookmark: Bookmark) -> Bool {
        var bookmark = bookmark
        guard let url = URLNormalizer.webURL(from: bookmark.url.absoluteString) else {
            storageError = "Bookmarks need a valid HTTP or HTTPS website address."
            return false
        }
        bookmark.url = url
        bookmark.title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmark.folder = bookmark.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = snapshot.bookmarks
        if let index = snapshot.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            snapshot.bookmarks[index] = bookmark
        } else {
            snapshot.bookmarks.append(bookmark)
        }
        guard save() else {
            snapshot.bookmarks = previous
            return false
        }
        return true
    }

    @discardableResult
    func setFavorite(_ isFavorite: Bool, for id: UUID) -> Bool {
        guard var bookmark = snapshot.bookmarks.first(where: { $0.id == id }) else {
            storageError = "This bookmark no longer exists."
            return false
        }
        bookmark.isFavorite = isFavorite
        return saveBookmark(bookmark)
    }

    @discardableResult
    func deleteBookmark(_ id: UUID) -> Bool {
        let previous = snapshot.bookmarks
        snapshot.bookmarks.removeAll { $0.id == id }
        guard save() else {
            snapshot.bookmarks = previous
            return false
        }
        return true
    }

    @discardableResult
    func addToReadingList(title: String, url: URL, now: Date = .now) -> Bool {
        guard let url = URLNormalizer.webURL(from: url.absoluteString) else {
            storageError = "Reading List needs a valid HTTP or HTTPS website address."
            return false
        }
        let previous = snapshot.readingList
        let existing = previous.first { $0.url == url }
        let entry = ReadingListItem(
            id: existing?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url, addedAt: now
        )
        snapshot.readingList.removeAll { $0.url == url }
        snapshot.readingList.insert(entry, at: 0)
        guard save() else {
            snapshot.readingList = previous
            return false
        }
        return true
    }

    @discardableResult
    func setReadingState(_ isRead: Bool, for id: UUID) -> Bool {
        guard let index = snapshot.readingList.firstIndex(where: { $0.id == id }) else {
            storageError = "This Reading List item no longer exists."
            return false
        }
        let previous = snapshot.readingList
        snapshot.readingList[index].isRead = isRead
        guard save() else {
            snapshot.readingList = previous
            return false
        }
        return true
    }

    @discardableResult
    func deleteReadingListItem(_ id: UUID) -> Bool {
        let previous = snapshot.readingList
        snapshot.readingList.removeAll { $0.id == id }
        guard save() else {
            snapshot.readingList = previous
            return false
        }
        return true
    }

    func recordVisit(title: String, url: URL, isPrivate: Bool, now: Date = .now) {
        guard !isPrivate, settings.historyRetentionDays > 0,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        snapshot.history.removeAll { $0.url == url }
        snapshot.history.insert(HistoryEntry(title: title, url: url, lastVisited: now), at: 0)
        pruneHistory(now: now)
        // Bound storage even if a site continuously changes its URL.
        snapshot.history = Array(snapshot.history.prefix(10_000))
        save()
    }

    func deleteHistory(_ id: UUID) {
        snapshot.history.removeAll { $0.id == id }
        save()
    }

    func clearHistory() {
        snapshot.history.removeAll()
        save()
    }

    func pruneHistory(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Double(settings.historyRetentionDays) * 86_400)
        snapshot.history.removeAll { $0.lastVisited < cutoff }
    }

    func setPermissions(_ value: SitePermissions, for origin: String) {
        snapshot.permissions[origin] = value
        save()
    }

    func clearPermissions() {
        snapshot.permissions.removeAll()
        save()
    }

    func saveSession(_ session: SavedSession) {
        snapshot.session = settings.restoreTabs ? session : SavedSession()
        save()
    }

    func saveDownloads(_ downloads: [DownloadItem]) {
        snapshot.downloads = downloads.filter { !$0.isPrivate }
        save()
    }

    @discardableResult
    private func save() -> Bool {
        guard !isReadOnly else {
            storageError = "Saved browser data is protected because it could not be read. Restart Duo Browser after resolving the storage problem."
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            return true
        } catch {
            logger.error("Browser data could not be saved.")
            storageError = "Your browser changes could not be saved. Check available device storage and try again."
            return false
        }
    }
}
