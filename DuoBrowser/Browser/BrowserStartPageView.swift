import SwiftUI

struct BrowserStartPageView: View {
    @ObservedObject var library: BrowserLibrary
    let isPrivate: Bool
    let open: (URL) -> Void
    let openInNewTab: (URL) -> Void
    let showBookmarks: () -> Void
    let showHistory: () -> Void
    let showReadingList: () -> Void
    let openDemo: () -> Void
    let openSettings: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 84), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: isPrivate ? "hand.raised.fill" : "globe")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(isPrivate ? "Private Browsing" : "Duo Browser")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(isPrivate
                        ? "Private tabs use temporary website storage. Websites and your network provider can still see your activity. Saved favorites remain available in both sessions."
                        : "Search the web or enter a website address below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Favorites")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Edit", action: showBookmarks)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Edit favorites")
                    }
                    if library.favorites.isEmpty {
                        Label(
                            "Save a page as a favorite from Add Bookmark in the browser menu.",
                            systemImage: "star"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(library.favorites) { bookmark in
                                favorite(bookmark)
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    shortcut("Bookmarks", icon: "book", action: showBookmarks)
                    Divider().padding(.leading, 44)
                    shortcut("History", icon: "clock", action: showHistory)
                    Divider().padding(.leading, 44)
                    shortcut("Reading List", icon: "eyeglasses", action: showReadingList)
                    Divider().padding(.leading, 44)
                    shortcut("Browser Settings", icon: "gearshape", action: openSettings)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Made for Duo")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Try native website controls without leaving the page.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Explore DuoKit Demo", action: openDemo)
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("browser.start-page")
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(isPrivate ? .purple : .accentColor)
    }

    private func favorite(_ bookmark: Bookmark) -> some View {
        Button { open(bookmark.url) } label: {
            VStack(spacing: 8) {
                Text(String(bookmark.displayTitle.prefix(1)).uppercased())
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                Text(bookmark.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open favorite \(bookmark.displayTitle)")
        .accessibilityHint(bookmark.url.host() ?? bookmark.url.absoluteString)
        .accessibilityIdentifier("favorite.\(bookmark.id.uuidString)")
        .contextMenu {
            Button("Open in New Tab", systemImage: "plus.square.on.square") {
                openInNewTab(bookmark.url)
            }
            ShareLink(item: bookmark.url)
            Button("Remove from Favorites", systemImage: "star.slash") {
                library.setFavorite(false, for: bookmark.id)
            }
        }
    }

    private func shortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(.tint)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
