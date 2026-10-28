import Foundation

struct ReadingListItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let url: URL
    var addedAt: Date
    var isRead: Bool

    init(id: UUID = UUID(), title: String, url: URL, addedAt: Date = .now, isRead: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.addedAt = addedAt
        self.isRead = isRead
    }

    var displayTitle: String {
        title.isEmpty ? (url.host() ?? url.absoluteString) : title
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || "\(title) \(url.absoluteString)".localizedCaseInsensitiveContains(query)
    }
}
