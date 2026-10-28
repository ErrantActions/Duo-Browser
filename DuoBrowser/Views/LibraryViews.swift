import SwiftUI

struct BookmarksView: View {
    @ObservedObject var library: BrowserLibrary
    let open: (URL) -> Void
    let openInNewTab: (URL) -> Void
    @State private var search = ""
    @State private var editing: Bookmark?
    @State private var collection = BookmarkCollection.all

    private var bookmarks: [Bookmark] {
        library.snapshot.bookmarks.filter { collection.contains($0) && $0.matches(search) }
    }

    var body: some View {
        List {
            Section {
                Picker("Collection", selection: $collection) {
                    Text("All Bookmarks").tag(BookmarkCollection.all)
                    Label("Favorites", systemImage: "star").tag(BookmarkCollection.favorites)
                    Label("Unfiled", systemImage: "tray").tag(BookmarkCollection.unfiled)
                    ForEach(library.bookmarkFolders, id: \.self) {
                        Label($0, systemImage: "folder").tag(BookmarkCollection.folder($0))
                    }
                }
            }
            Section {
                if bookmarks.isEmpty {
                    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView(
                            "No Bookmarks Here", systemImage: "bookmark",
                            description: Text("Add pages from the browser menu, or choose another collection.")
                        )
                    }
                }
                ForEach(bookmarks) { bookmark in
                    Button { open(bookmark.url) } label: {
                        WebsiteRow(
                            title: bookmark.displayTitle, url: bookmark.url,
                            icon: bookmark.isFavorite ? "star.fill" : "bookmark"
                        )
                    }
                    .accessibilityIdentifier("bookmark.\(bookmark.id.uuidString)")
                    .contextMenu {
                        Button("Open in New Tab", systemImage: "plus.square.on.square") {
                            openInNewTab(bookmark.url)
                        }
                        Button("Edit", systemImage: "pencil") { editing = bookmark }
                        Button(bookmark.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                               systemImage: bookmark.isFavorite ? "star.slash" : "star") {
                            library.setFavorite(!bookmark.isFavorite, for: bookmark.id)
                        }
                        ShareLink(item: bookmark.url)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { library.deleteBookmark(bookmark.id) }
                        Button("Edit") { editing = bookmark }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search Bookmarks")
        .sheet(item: $editing) { bookmark in
            NavigationStack { BookmarkEditor(library: library, bookmark: bookmark) { editing = nil } }
        }
        .onChange(of: library.bookmarkFolders) { _, folders in
            if case .folder(let name) = collection, !folders.contains(name) { collection = .all }
        }
    }
}

struct BookmarkEditor: View {
    @ObservedObject var library: BrowserLibrary
    @State var bookmark: Bookmark
    let done: () -> Void
    @State private var address = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Page") {
                TextField("Title", text: $bookmark.title)
                    .accessibilityLabel("Bookmark title")
                TextField("Address", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Bookmark address")
            }
            Section("Location") {
                TextField("Folder (optional)", text: $bookmark.folder)
                if !library.bookmarkFolders.isEmpty {
                    Menu("Choose Existing Folder") {
                        Button("Unfiled") { bookmark.folder = "" }
                        ForEach(library.bookmarkFolders, id: \.self) { folder in
                            Button(folder) { bookmark.folder = folder }
                        }
                    }
                }
            }
            Section {
                Toggle("Show on Start Page", isOn: $bookmark.isFavorite)
                    .accessibilityIdentifier("bookmark.favorite")
            } footer: {
                Text("Favorites are saved locally and appear on the start page in regular and private tabs.")
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Bookmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: done)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear { address = bookmark.url.absoluteString }
    }

    private func save() {
        guard let url = URLNormalizer.webURL(from: address) else {
            error = "Enter a valid HTTP or HTTPS address."
            return
        }
        bookmark.url = url
        guard library.saveBookmark(bookmark) else {
            error = library.storageError ?? "The bookmark could not be saved. Try again."
            library.storageError = nil
            return
        }
        done()
    }
}

struct HistoryView: View {
    @ObservedObject var library: BrowserLibrary
    let open: (URL) -> Void
    let openInNewTab: (URL) -> Void
    @Environment(\.calendar) private var calendar
    @State private var search = ""
    @State private var confirmsClear = false
    private var days: [HistoryDay] {
        HistoryDay.grouped(library.snapshot.history, matching: search, calendar: calendar)
    }

    var body: some View {
        List {
            ForEach(days) { day in
                Section(dayTitle(day.date)) {
                    ForEach(day.entries) { entry in
                        Button { open(entry.url) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                WebsiteRow(title: entry.title, url: entry.url, icon: "globe")
                                Text(entry.lastVisited, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Open in New Tab", systemImage: "plus.square.on.square") {
                                openInNewTab(entry.url)
                            }
                            ShareLink(item: entry.url)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { library.deleteHistory(entry.id) }
                        }
                    }
                }
            }
        }
        .overlay {
            if library.snapshot.history.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock",
                                       description: Text("Private browsing does not save history."))
            } else if days.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search History")
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Clear History", role: .destructive) { confirmsClear = true }
                    .disabled(library.snapshot.history.isEmpty)
            }
        }
        .confirmationDialog("Clear all browsing history?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { library.clearHistory() }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct WebsiteRow: View {
    let title: String
    let url: URL
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? (url.host() ?? url.absoluteString) : title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}

struct DownloadsView: View {
    @ObservedObject var manager: DownloadManager
    @State private var sharing: SharedPage?
    @State private var error: String?
    @State private var pendingDeletion: DownloadItem?
    @State private var previewing: FilePreview?

    var body: some View {
        List(manager.items) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.filename)
                Text(item.status.rawValue.capitalized).font(.caption)
                if item.isPrivate { Text("Private download - file remains on device").font(.caption) }
                if let message = item.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if manager.cancellingIDs.contains(item.id) {
                    ProgressView("Stopping Download")
                } else if item.status == .downloading {
                    if let progress = item.fractionCompleted { ProgressView(value: progress) }
                    else { ProgressView() }
                    Button("Cancel") {
                        Task { await manager.cancel(item.id) }
                    }
                } else if item.status == .completed {
                    Button("Preview File", systemImage: "doc.richtext") {
                        do {
                            let url = try manager.fileURL(for: item)
                            guard FilePreview.canPreview(url) else {
                                error = "iOS cannot preview this file type. Use Open or Share to choose an app."
                                return
                            }
                            previewing = FilePreview(url: url, title: item.filename)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    Button("Open or Share", systemImage: "square.and.arrow.up") {
                        do {
                            sharing = SharedPage(url: try manager.fileURL(for: item))
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .swipeActions {
                Button("Delete", role: .destructive) { pendingDeletion = item }
                    .disabled(item.status == .downloading || manager.cancellingIDs.contains(item.id))
            }
        }
        .overlay {
            if manager.items.isEmpty { ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle") }
        }
        .navigationTitle("Downloads")
        .sheet(item: $sharing) { ShareSheet(url: $0.url) }
        .sheet(item: $previewing) { preview in
            NavigationStack {
                preview
                    .navigationTitle(preview.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { previewing = nil }
                        }
                    }
            }
        }
        .confirmationDialog("Delete Download?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            if let item = pendingDeletion {
                Button("Delete Download and File", role: .destructive) {
                    do {
                        try manager.remove(item.id)
                    } catch {
                        self.error = error.localizedDescription
                    }
                    pendingDeletion = nil
                }
            }
        } message: {
            Text("This removes the download entry and its file from this device. It cannot be undone.")
        }
        .alert("Downloads", isPresented: Binding(
            get: { error != nil || manager.operationError != nil },
            set: { if !$0 { error = nil; manager.operationError = nil } }
        )) {
            Button("OK") { error = nil; manager.operationError = nil }
        } message: {
            Text(error ?? manager.operationError ?? "")
        }
    }
}
