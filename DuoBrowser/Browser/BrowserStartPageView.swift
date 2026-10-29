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
                hero

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
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Your favorites, close at hand.", systemImage: "star.circle")
                                .font(.headline)
                            Text("Use Add Bookmark in the browser menu to pin the sites you return to.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(library.favorites) { bookmark in
                                favorite(bookmark)
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 250 : 140), spacing: 14)], spacing: 14) {
                    shortcut("Bookmarks", icon: "book", action: showBookmarks)
                    shortcut("History", icon: "clock", action: showHistory)
                    shortcut("Reading List", icon: "eyeglasses", action: showReadingList)
                    shortcut("Browser Settings", icon: "gearshape", action: openSettings)
                }

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
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("browser.start-page")
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(isPrivate ? .purple : .accentColor)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: isPrivate ? "hand.raised.fill" : "globe")
                    .font(.system(size: 28, weight: .medium))
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Spacer()
                Label(isPrivate ? "Private session" : "Made for iPhone", systemImage: isPrivate ? "lock" : "iphone")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            Text(isPrivate ? "A little more private." : "Your web.\nRoom to explore.")
                .font(.system(.largeTitle, design: .rounded).bold())
                .accessibilityAddTraits(.isHeader)
            Text(isPrivate
                ? "Temporary website storage. No saved browsing history. Your network and the websites you visit can still see your activity."
                : "Duo Browser keeps the page in focus, with native controls, thoughtful reading tools, and on-device intelligence.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(24)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: isPrivate
                ? [Color(red: 0.19, green: 0.12, blue: 0.34), Color(red: 0.37, green: 0.22, blue: 0.51)]
                : [Color(red: 0.08, green: 0.18, blue: 0.38), Color(red: 0.19, green: 0.38, blue: 0.69)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
    }

    private func favorite(_ bookmark: Bookmark) -> some View {
        Button { open(bookmark.url) } label: {
            VStack(spacing: 8) {
                Text(String(bookmark.displayTitle.prefix(1)).uppercased())
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(favoriteColor(bookmark).gradient, in: RoundedRectangle(cornerRadius: 20))
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
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func favoriteColor(_ bookmark: Bookmark) -> Color {
        let colors: [Color] = [.blue, .indigo, .teal, .purple, .brown]
        let index = (bookmark.url.host ?? bookmark.displayTitle).unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        return colors[index]
    }
}
