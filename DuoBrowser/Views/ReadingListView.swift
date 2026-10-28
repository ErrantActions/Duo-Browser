import SwiftUI

struct ReadingListView: View {
    @ObservedObject var library: BrowserLibrary
    let open: (URL) -> Void
    let openInNewTab: (URL) -> Void
    @State private var unreadOnly = false
    @State private var search = ""

    private var entries: [ReadingListItem] {
        library.snapshot.readingList.filter { (!unreadOnly || !$0.isRead) && $0.matches(search) }
    }

    var body: some View {
        List {
            Section {
                Picker("Reading Status", selection: $unreadOnly) {
                    Text("All").tag(false)
                    Text("Unread").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Saved links stay on this device. Pages are not downloaded for offline reading. Use the swipe actions to mark a link read or unread.")
            }
            Section {
                if entries.isEmpty {
                    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView(
                            unreadOnly ? "No Unread Pages" : "No Saved Pages",
                            systemImage: "eyeglasses",
                            description: Text("Use Add to Reading List in the browser menu to save a page for later.")
                        )
                    }
                }
                ForEach(entries) { entry in
                    Button { open(entry.url) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            WebsiteRow(
                                title: entry.displayTitle, url: entry.url,
                                icon: entry.isRead ? "checkmark.circle" : "circle"
                            )
                            Text(entry.isRead ? "Read" : "Unread")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("reading-list.\(entry.id.uuidString)")
                    .contextMenu {
                        Button("Open in New Tab", systemImage: "plus.square.on.square") {
                            openInNewTab(entry.url)
                        }
                        Button(entry.isRead ? "Mark Unread" : "Mark Read",
                               systemImage: entry.isRead ? "circle" : "checkmark.circle") {
                            library.setReadingState(!entry.isRead, for: entry.id)
                        }
                        ShareLink(item: entry.url)
                    }
                    .swipeActions(edge: .leading) {
                        Button(entry.isRead ? "Mark Unread" : "Mark Read") {
                            library.setReadingState(!entry.isRead, for: entry.id)
                        }
                        .tint(.blue)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { library.deleteReadingListItem(entry.id) }
                    }
                }
            }
        }
        .navigationTitle("Reading List")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search Reading List")
    }
}
