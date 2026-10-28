import QuickLook
import XCTest
@testable import DuoBrowser

@MainActor
final class DownloadManagerTests: XCTestCase {
    private func storage() throws -> (BrowserLibrary, URL) {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return (BrowserLibrary(fileURL: root.appendingPathComponent("library.json")), downloads)
    }

    private func item(
        status: DownloadItem.Status = .completed,
        isPrivate: Bool = false
    ) -> DownloadItem {
        let id = UUID()
        return DownloadItem(
            id: id, filename: "report.pdf", relativePath: "\(id.uuidString)-report.pdf",
            status: status, isPrivate: isPrivate
        )
    }

    private func writeFile(_ item: DownloadItem, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(try XCTUnwrap(item.relativePath))
        try Data("download contents".utf8).write(to: url)
        return url
    }

    func testSuggestedNamesCannotSupplyPaths() {
        XCTAssertEqual(DownloadItem.sanitizedFilename("../../report.pdf"), "report.pdf")
        XCTAssertEqual(DownloadItem.sanitizedFilename("C:\\Downloads\\report.pdf"), "report.pdf")
        XCTAssertEqual(DownloadItem.sanitizedFilename(" report\n.pdf\u{0000} "), "report.pdf")
        for value in ["", ".", "..", "../../", " \n "] {
            XCTAssertEqual(DownloadItem.sanitizedFilename(value), "download")
        }
    }

    func testFilenameLimitCountsUTF8BytesAndPreservesExtension() {
        for value in [
            String(repeating: "a", count: 300) + ".pdf",
            String(repeating: "\u{1F30D}", count: 160) + ".pdf",
            String(repeating: "e\u{301}", count: 160) + ".pdf"
        ] {
            let filename = DownloadItem.sanitizedFilename(value)
            XCTAssertLessThanOrEqual(filename.utf8.count, 180)
            XCTAssertTrue(filename.hasSuffix(".pdf"))
            XCTAssertFalse(filename.contains("\u{FFFD}"))
            XCTAssertLessThanOrEqual("\(UUID().uuidString)-\(filename)".utf8.count, 255)
        }
    }

    func testDeleteRemovesOnlyTheSelectedFileAndPersistsTheList() throws {
        let (library, directory) = try storage()
        let first = item()
        let second = item()
        library.saveDownloads([first, second])
        let firstURL = try writeFile(first, in: directory)
        let secondURL = try writeFile(second, in: directory)
        let manager = DownloadManager(library: library, directory: directory)

        XCTAssertEqual(try manager.fileURL(for: first), firstURL)
        try manager.remove(first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(manager.items.map(\.id), [second.id])
        XCTAssertEqual(library.snapshot.downloads.map(\.id), [second.id])
    }

    func testInterruptedDownloadBecomesFailedAndItsPartialFileIsRemoved() throws {
        let (library, directory) = try storage()
        let interrupted = item(status: .downloading)
        library.saveDownloads([interrupted])
        let url = try writeFile(interrupted, in: directory)
        let manager = DownloadManager(library: library, directory: directory)

        XCTAssertEqual(manager.items.first?.status, .failed)
        XCTAssertNil(manager.items.first?.relativePath)
        XCTAssertNotNil(manager.items.first?.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(library.snapshot.downloads.first?.status, .failed)
        XCTAssertNil(manager.operationError)
    }

    func testMissingCompletedFileHasAnErrorButItsEntryCanBeDeleted() throws {
        let (library, directory) = try storage()
        let missing = item()
        library.saveDownloads([missing])
        let manager = DownloadManager(library: library, directory: directory)
        XCTAssertThrowsError(try manager.fileURL(for: missing))
        try manager.remove(missing.id)
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertTrue(library.snapshot.downloads.isEmpty)
    }

    func testStoredPathsCannotDeleteOutsideTheDownloadsDirectory() throws {
        let (library, directory) = try storage()
        let sentinel = directory.deletingLastPathComponent().appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        var invalid = item()
        for path in [
            "../keep.txt", "\(invalid.id.uuidString)-../keep.txt",
            "\(invalid.id.uuidString)-..\\keep.txt", ".",
            "\(UUID().uuidString)-other.pdf"
        ] {
            invalid.relativePath = path
            library.saveDownloads([invalid])
            let manager = DownloadManager(library: library, directory: directory)
            XCTAssertThrowsError(try manager.fileURL(for: invalid))
            XCTAssertThrowsError(try manager.remove(invalid.id))
            XCTAssertEqual(manager.items.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        }
    }

    func testInvalidInterruptedPathSurfacesCleanupFailure() throws {
        let (library, directory) = try storage()
        var invalid = item(status: .downloading)
        invalid.relativePath = "../keep.txt"
        library.saveDownloads([invalid])
        let manager = DownloadManager(library: library, directory: directory)
        XCTAssertNotNil(manager.operationError)
        XCTAssertNotNil(manager.items.first?.message)
        XCTAssertEqual(manager.items.first?.relativePath, invalid.relativePath)
    }

    func testDeletionNeverRecursivelyRemovesADirectory() throws {
        let (library, directory) = try storage()
        let download = item()
        let folder = directory.appendingPathComponent(try XCTUnwrap(download.relativePath), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let sentinel = folder.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        library.saveDownloads([download])
        let manager = DownloadManager(library: library, directory: directory)
        XCTAssertThrowsError(try manager.remove(download.id))
        XCTAssertThrowsError(try manager.fileURL(for: download))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertEqual(manager.items.count, 1)
    }

    func testCancellingAllWithNoTransfersKeepsCompletedFiles() async throws {
        let (library, directory) = try storage()
        let completed = item()
        library.saveDownloads([completed])
        let url = try writeFile(completed, in: directory)
        let manager = DownloadManager(library: library, directory: directory)
        await manager.cancelAll()
        XCTAssertEqual(manager.items.first?.status, .completed)
        XCTAssertTrue(manager.cancellingIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPrivateDownloadRecordsNeverEnterPersistentLibrary() throws {
        let (library, _) = try storage()
        let regular = item()
        let privateItem = item(isPrivate: true)
        library.saveDownloads([regular, privateItem])
        XCTAssertEqual(library.snapshot.downloads.map(\.id), [regular.id])
    }

    func testFilePreviewUsesOneValidatedFileAndItsOriginalTitle() throws {
        let (library, directory) = try storage()
        let completed = item()
        library.saveDownloads([completed])
        let file = try writeFile(completed, in: directory)
        let manager = DownloadManager(library: library, directory: directory)
        let preview = FilePreview(url: try manager.fileURL(for: completed), title: completed.filename)
        let coordinator = preview.makeCoordinator()
        let controller = QLPreviewController()
        XCTAssertEqual(coordinator.numberOfPreviewItems(in: controller), 1)
        let previewItem = coordinator.previewController(controller, previewItemAt: 0)
        XCTAssertEqual(previewItem.previewItemURL, file)
        XCTAssertEqual(previewItem.previewItemTitle, "report.pdf")
    }
}
