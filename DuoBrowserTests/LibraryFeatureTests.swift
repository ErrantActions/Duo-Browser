import XCTest
@testable import DuoBrowser

@MainActor
final class LibraryFeatureTests: XCTestCase {
    private func storage() throws -> (BrowserLibrary, URL) {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library.json")
        return (BrowserLibrary(fileURL: file), file)
    }

    private func website(_ path: String = "") throws -> URL {
        try XCTUnwrap(URL(string: "https://example.com\(path)"))
    }

    func testOlderLibraryLoadsWithoutFavoritesOrReadingList() throws {
        let (_, file) = try storage()
        var old = LibrarySnapshot()
        let bookmark = Bookmark(title: "Existing", url: try website(), folder: "Work")
        old.bookmarks = [bookmark]
        old.session = SavedSession(
            tabs: [RestoredTab(url: try website(), requestsDesktopSite: true, pageZoom: 1.5)]
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "readingList")
        var bookmarks = try XCTUnwrap(json["bookmarks"] as? [[String: Any]])
        bookmarks[0].removeValue(forKey: "isFavorite")
        json["bookmarks"] = bookmarks
        var session = try XCTUnwrap(json["session"] as? [String: Any])
        var tabs = try XCTUnwrap(session["tabs"] as? [[String: Any]])
        tabs[0].removeValue(forKey: "pageZoom")
        session["tabs"] = tabs
        json["session"] = session
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let library = BrowserLibrary(fileURL: file)
        XCTAssertNil(library.storageError)
        XCTAssertEqual(library.snapshot.bookmarks, [bookmark])
        XCTAssertFalse(library.snapshot.bookmarks[0].isFavorite)
        XCTAssertTrue(library.snapshot.readingList.isEmpty)
        XCTAssertEqual(library.snapshot.session.tabs[0].pageZoom, 1)
        XCTAssertTrue(library.snapshot.session.tabs[0].requestsDesktopSite)
    }

    func testMalformedNewFieldIsNotSilentlyDefaultedOrOverwritten() throws {
        let (_, file) = try storage()
        let snapshot = LibrarySnapshot()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json["readingList"] = "not an array"
        let original = try JSONSerialization.data(withJSONObject: json)
        try original.write(to: file)

        let library = BrowserLibrary(fileURL: file)
        XCTAssertNotNil(library.storageError)
        XCTAssertFalse(library.saveBookmark(Bookmark(title: "New", url: try website())))
        XCTAssertTrue(library.snapshot.bookmarks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testFavoritesAndFoldersPersistWithoutDuplicatingBookmarks() throws {
        let (library, file) = try storage()
        let bookmark = Bookmark(title: " Example ", url: try website(), folder: " Work ")
        XCTAssertTrue(library.saveBookmark(bookmark))
        XCTAssertTrue(library.setFavorite(true, for: bookmark.id))
        XCTAssertEqual(library.snapshot.bookmarks.count, 1)
        XCTAssertEqual(library.favorites.first?.id, bookmark.id)
        XCTAssertEqual(library.favorites.first?.title, "Example")
        XCTAssertEqual(library.bookmarkFolders, ["Work"])

        let restored = BrowserLibrary(fileURL: file)
        XCTAssertEqual(restored.favorites.first?.id, bookmark.id)
        XCTAssertTrue(restored.setFavorite(false, for: bookmark.id))
        XCTAssertTrue(restored.favorites.isEmpty)
        XCTAssertEqual(restored.snapshot.bookmarks.count, 1)
        XCTAssertTrue(restored.deleteBookmark(bookmark.id))
        XCTAssertTrue(BrowserLibrary(fileURL: file).snapshot.bookmarks.isEmpty)
    }

    func testBookmarkCollectionAndSearchMatchActualSavedFields() throws {
        let favorite = Bookmark(title: "Reference", url: try website("/guide"), folder: "Work", isFavorite: true)
        let unfiled = Bookmark(title: "", url: try website("/notes"))
        XCTAssertTrue(BookmarkCollection.all.contains(favorite))
        XCTAssertTrue(BookmarkCollection.favorites.contains(favorite))
        XCTAssertFalse(BookmarkCollection.favorites.contains(unfiled))
        XCTAssertTrue(BookmarkCollection.folder("Work").contains(favorite))
        XCTAssertFalse(BookmarkCollection.folder("work").contains(favorite))
        XCTAssertTrue(BookmarkCollection.unfiled.contains(unfiled))
        XCTAssertFalse(BookmarkCollection.unfiled.contains(favorite))
        XCTAssertTrue(favorite.matches("  REFERENCE "))
        XCTAssertTrue(favorite.matches("example.com/guide"))
        XCTAssertTrue(favorite.matches("work"))
        XCTAssertFalse(favorite.matches("missing"))
        XCTAssertEqual(unfiled.displayTitle, "example.com")
    }

    func testInvalidSavedPageSchemesAreRejectedWithAnError() throws {
        let (library, _) = try storage()
        for value in ["file:///tmp/test", "javascript:alert(1)", "data:text/html,test"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertFalse(library.saveBookmark(Bookmark(title: "Invalid", url: url)))
            XCTAssertFalse(library.addToReadingList(title: "Invalid", url: url))
            XCTAssertNotNil(library.storageError)
        }
        XCTAssertTrue(library.snapshot.bookmarks.isEmpty)
        XCTAssertTrue(library.snapshot.readingList.isEmpty)
    }

    func testBookmarkWriteFailureDoesNotApplyAnUnsavedEditOrDeletion() throws {
        let (library, file) = try storage()
        let bookmark = Bookmark(title: "Original", url: try website())
        XCTAssertTrue(library.saveBookmark(bookmark))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var edited = bookmark
        edited.title = "Unsaved"

        XCTAssertFalse(library.saveBookmark(edited))
        XCTAssertEqual(library.snapshot.bookmarks, [bookmark])
        XCTAssertFalse(library.setFavorite(true, for: bookmark.id))
        XCTAssertTrue(library.favorites.isEmpty)
        XCTAssertFalse(library.deleteBookmark(bookmark.id))
        XCTAssertEqual(library.snapshot.bookmarks, [bookmark])
        XCTAssertNotNil(library.storageError)
    }

    func testReadingListResaveKeepsIdentityAndReturnsItemToUnread() throws {
        let (library, file) = try storage()
        let url = try website("/later")
        XCTAssertTrue(library.addToReadingList(title: "First", url: url))
        let id = try XCTUnwrap(library.snapshot.readingList.first?.id)
        XCTAssertTrue(library.setReadingState(true, for: id))
        XCTAssertTrue(library.snapshot.readingList[0].isRead)
        let later = Date.now.addingTimeInterval(30)
        XCTAssertTrue(library.addToReadingList(title: " Updated ", url: url, now: later))
        XCTAssertEqual(library.snapshot.readingList.count, 1)
        XCTAssertEqual(library.snapshot.readingList[0].id, id)
        XCTAssertEqual(library.snapshot.readingList[0].title, "Updated")
        XCTAssertEqual(library.snapshot.readingList[0].addedAt, later)
        XCTAssertFalse(library.snapshot.readingList[0].isRead)

        let restored = BrowserLibrary(fileURL: file)
        XCTAssertEqual(restored.snapshot.readingList, library.snapshot.readingList)
        XCTAssertTrue(restored.snapshot.readingList[0].matches("EXAMPLE.COM/LATER"))
        XCTAssertTrue(restored.deleteReadingListItem(id))
        XCTAssertTrue(BrowserLibrary(fileURL: file).snapshot.readingList.isEmpty)
    }

    func testReadingListWriteFailureRollsBackItsChanges() throws {
        let (library, file) = try storage()
        XCTAssertTrue(library.addToReadingList(title: "Original", url: try website()))
        let original = library.snapshot.readingList
        let id = try XCTUnwrap(original.first?.id)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

        XCTAssertFalse(library.addToReadingList(title: "Unsaved", url: try website("/new")))
        XCTAssertEqual(library.snapshot.readingList, original)
        XCTAssertFalse(library.setReadingState(true, for: id))
        XCTAssertEqual(library.snapshot.readingList, original)
        XCTAssertFalse(library.deleteReadingListItem(id))
        XCTAssertEqual(library.snapshot.readingList, original)
        XCTAssertNotNil(library.storageError)
    }

    func testHistoryGroupsByLocalCalendarDayAndSortsNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let beforeDST = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1)))
        let afterDST = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3)))
        let previousDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23)))
        let entries = [
            HistoryEntry(title: "Before", url: try website("/before"), lastVisited: beforeDST),
            HistoryEntry(title: "Earlier", url: try website("/earlier"), lastVisited: previousDay),
            HistoryEntry(title: "After", url: try website("/after"), lastVisited: afterDST)
        ]
        let days = HistoryDay.grouped(entries, matching: "", calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].date, calendar.startOfDay(for: beforeDST))
        XCTAssertEqual(days[0].entries.map(\.title), ["After", "Before"])
        XCTAssertEqual(days[1].entries.map(\.title), ["Earlier"])
        XCTAssertEqual(HistoryDay.grouped(entries, matching: "EXAMPLE.COM/AFTER", calendar: calendar).flatMap(\.entries).count, 1)
        XCTAssertTrue(HistoryDay.grouped(entries, matching: "not found", calendar: calendar).isEmpty)
    }

    func testInvalidPersistedPageZoomIsRejected() throws {
        for zoom in [0.0, 0.49, 3.01] {
            let data = try JSONSerialization.data(withJSONObject: [
                "requestsDesktopSite": false, "pageZoom": zoom
            ])
            XCTAssertThrowsError(try JSONDecoder().decode(RestoredTab.self, from: data))
        }
    }
}
