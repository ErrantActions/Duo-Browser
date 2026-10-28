import SwiftUI

struct RecentlyClosedTabsView: View {
    @ObservedObject var manager: BrowserTabManager
    let done: () -> Void

    var body: some View {
        List {
            Section {
                if manager.recentlyClosedTabs.isEmpty {
                    ContentUnavailableView(
                        "No Recently Closed Tabs", systemImage: "clock.arrow.circlepath",
                        description: Text("Regular pages you close during this app session appear here. Private tabs are never included.")
                    )
                }
                ForEach(manager.recentlyClosedTabs) { tab in
                    Button {
                        if manager.reopen(tab.id) != nil { done() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            WebsiteRow(title: tab.title, url: tab.url, icon: "clock.arrow.circlepath")
                            Text(tab.closedAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Reopen \(tab.title.isEmpty ? (tab.url.host() ?? tab.url.absoluteString) : tab.title)")
                    .swipeActions {
                        Button("Forget", role: .destructive) { manager.forgetClosedTab(tab.id) }
                    }
                }
            } footer: {
                Text("This list stays in memory only, up to your maximum tab count. Reopening restores the address, page zoom, and desktop/mobile preference, not the old page's form data or back/forward history.")
            }
        }
        .navigationTitle("Recently Closed Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
