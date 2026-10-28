import Combine
import Foundation
import OSLog
import WebKit

struct DownloadItem: Identifiable, Codable {
    enum Status: String, Codable {
        case downloading
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    var filename: String
    var relativePath: String?
    var status: Status
    var fractionCompleted: Double?
    var message: String?
    var isPrivate: Bool

    static func sanitizedFilename(_ suggestion: String) -> String {
        let component = suggestion.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let cleaned = String(component.filter { !$0.isASCIIControl })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return "download" }
        guard cleaned.utf8.count > 180 else { return cleaned }

        let fileExtension = (cleaned as NSString).pathExtension
        let suffix = !fileExtension.isEmpty && fileExtension.utf8.count <= 20 ? ".\(fileExtension)" : ""
        let stem = suffix.isEmpty ? cleaned : String(cleaned.dropLast(suffix.count))
        var result = ""
        let limit = 180 - suffix.utf8.count
        for character in stem {
            guard result.utf8.count + character.utf8.count <= limit else { break }
            result.append(character)
        }
        if result.isEmpty { result = "download" }
        return result + suffix
    }
}

enum DownloadManagementError: LocalizedError {
    case missingItem
    case stillActive
    case unavailableFile
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .missingItem: "This download is no longer in the list."
        case .stillActive: "Cancel this download and wait for it to stop before deleting it."
        case .unavailableFile: "This downloaded file is not available."
        case .invalidPath: "The saved download location is invalid. No file was opened or deleted."
        }
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    @Published private(set) var items: [DownloadItem]
    @Published private(set) var cancellingIDs: Set<UUID> = []
    @Published var operationError: String?
    private let library: BrowserLibrary
    private var active: [UUID: WKDownload] = [:]
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    private var observations: [UUID: NSKeyValueObservation] = [:]
    private var cancellations: [UUID: Task<Void, Never>] = [:]
    private let directory: URL
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "Downloads")

    init(
        library: BrowserLibrary,
        directory: URL = URL.documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
    ) {
        self.library = library
        self.directory = directory
        items = library.snapshot.downloads.map {
            var item = $0
            if item.status == .downloading {
                item.status = .failed
                item.message = "This download was interrupted. Open its website to try again."
            }
            return item
        }
        super.init()
        for item in items where item.status != .completed {
            removePartialFile(for: item.id)
        }
        persist()
    }

    func register(_ download: WKDownload, isPrivate: Bool) {
        let id = UUID()
        active[id] = download
        identifiers[ObjectIdentifier(download)] = id
        items.insert(DownloadItem(
            id: id, filename: "Preparing Download", status: .downloading, isPrivate: isPrivate
        ), at: 0)
        download.delegate = self
        observations[id] = download.progress.observe(\.fractionCompleted, options: [.new]) {
            [weak self] progress, _ in
            let fraction = progress.totalUnitCount > 0 ? progress.fractionCompleted : nil
            Task { @MainActor [weak self] in
                self?.update(id) {
                    if $0.status == .downloading { $0.fractionCompleted = fraction }
                }
            }
        }
        persist()
    }

    func cancel(_ id: UUID) async {
        if let cancellation = cancellations[id] {
            await cancellation.value
            return
        }
        guard let download = active[id] else { return }
        cancellingIDs.insert(id)
        update(id) { $0.status = .cancelled; $0.message = "Download cancelled." }
        persist()
        let cancellation = Task { @MainActor [weak self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                download.cancel { _ in continuation.resume() }
            }
            guard let self else { return }
            self.removePartialFile(for: id)
            self.finish(id, download: download)
        }
        cancellations[id] = cancellation
        await cancellation.value
        cancellations.removeValue(forKey: id)
    }

    func cancelAll() async {
        for id in Array(active.keys) {
            await cancel(id)
        }
    }

    func fileURL(for item: DownloadItem) throws -> URL {
        guard item.status == .completed, let url = try storedFileURL(for: item),
              FileManager.default.fileExists(atPath: url.path) else {
            throw DownloadManagementError.unavailableFile
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DownloadManagementError.invalidPath
        }
        return url
    }

    func remove(_ id: UUID) throws {
        guard let item = items.first(where: { $0.id == id }) else {
            throw DownloadManagementError.missingItem
        }
        guard active[id] == nil else { throw DownloadManagementError.stillActive }
        try deleteStoredFile(for: item)
        items.removeAll { $0.id == id }
        persist()
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        guard let id = identifiers[ObjectIdentifier(download)], !cancellingIDs.contains(id) else {
            completionHandler(nil)
            return
        }
        // A website-supplied filename is never interpreted as an application path.
        let filename = DownloadItem.sanitizedFilename(suggestedFilename)
        let relativePath = "\(id.uuidString)-\(filename)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            update(id) { $0.filename = filename; $0.relativePath = relativePath }
            // Persist the destination before bytes arrive so interrupted files can be cleaned up.
            persist()
            completionHandler(directory.appendingPathComponent(relativePath))
        } catch {
            logger.error("Could not create download destination.")
            update(id) {
                $0.status = .failed
                $0.message = "The download could not be saved. Check device storage."
            }
            completionHandler(nil)
            finish(id, download: download)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = identifiers[ObjectIdentifier(download)], !cancellingIDs.contains(id) else { return }
        update(id) { $0.status = .completed; $0.fractionCompleted = 1 }
        finish(id, download: download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = identifiers[ObjectIdentifier(download)], !cancellingIDs.contains(id) else { return }
        logger.error("A download failed.")
        update(id) {
            $0.status = .failed
            $0.message = "Download failed. Return to the website and try again."
        }
        removePartialFile(for: id)
        finish(id, download: download)
    }

    private func storedFileURL(for item: DownloadItem) throws -> URL? {
        guard let path = item.relativePath else { return nil }
        guard path.hasPrefix("\(item.id.uuidString)-"), path.utf8.count <= 255,
              !path.contains("/"), !path.contains("\\"),
              !path.contains(where: \.isASCIIControl) else {
            throw DownloadManagementError.invalidPath
        }
        return directory.appendingPathComponent(path)
    }

    private func removePartialFile(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.status != .completed else { return }
        do {
            try deleteStoredFile(for: item)
            update(id) { $0.relativePath = nil }
        } catch {
            logger.error("An incomplete download could not be removed.")
            let message = "An incomplete download could not be removed. Open Downloads and delete the affected entry to try again."
            update(id) { $0.message = message }
            operationError = message
        }
    }

    private func deleteStoredFile(for item: DownloadItem) throws {
        guard let url = try storedFileURL(for: item),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == false else { throw DownloadManagementError.invalidPath }
        try FileManager.default.removeItem(at: url)
    }

    private func update(_ id: UUID, change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func finish(_ id: UUID, download: WKDownload) {
        observations.removeValue(forKey: id)
        cancellingIDs.remove(id)
        active.removeValue(forKey: id)
        identifiers.removeValue(forKey: ObjectIdentifier(download))
        download.delegate = nil
        persist()
    }

    private func persist() {
        library.saveDownloads(items)
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
