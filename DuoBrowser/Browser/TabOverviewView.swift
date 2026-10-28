import OSLog
import SwiftUI
import WebKit

struct TabOverviewView: View {
    @ObservedObject var manager: BrowserTabManager
    let done: () -> Void
    let showRecentlyClosed: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsPrivate = false
    @State private var search = ""
    @State private var confirmsCloseAll = false

    private var sessionTabs: [BrowserViewModel] {
        manager.tabs.filter { $0.isPrivate == showsPrivate }
    }

    private var filteredTabs: [BrowserViewModel] {
        sessionTabs.filter {
            search.isEmpty || $0.pageTitle.localizedCaseInsensitiveContains(search)
                || $0.addressText.localizedCaseInsensitiveContains(search)
                || ($0.showingStartPage && "Start Page".localizedCaseInsensitiveContains(search))
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Browsing Session", selection: $showsPrivate) {
                Text("Tabs").tag(false)
                Text("Private").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("tabs.session")
            .padding()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredTabs, id: \.id) { tab in
                        TabCard(tab: tab, selected: tab.id == manager.selectedID) {
                            manager.select(tab.id)
                            done()
                        } close: {
                            manager.close(tab.id)
                        }
                    }
                }
                .padding([.horizontal, .bottom], 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if filteredTabs.isEmpty {
                    if !search.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView(
                            showsPrivate ? "No Private Tabs" : "No Tabs",
                            systemImage: showsPrivate ? "hand.raised" : "square.on.square",
                            description: Text(showsPrivate
                                ? "Private tabs keep browsing history and website storage out of your regular session."
                                : "Open a new tab to start browsing.")
                        )
                    }
                }
            }

            HStack {
                Button {
                    if manager.addTab(isPrivate: showsPrivate) != nil { done() }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(showsPrivate ? "New Private Tab" : "New Tab")
                .contextMenu {
                    if let tab = manager.recentlyClosedTabs.first {
                        Button("Reopen Last Closed Tab", systemImage: "arrow.uturn.backward") {
                            if manager.reopen(tab.id) != nil { done() }
                        }
                    }
                    Button("Recently Closed Tabs", systemImage: "clock.arrow.circlepath", action: showRecentlyClosed)
                }
                Spacer()
                Text("\(sessionTabs.count) \(sessionTabs.count == 1 ? "Tab" : "Tabs")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: done)
                    .fontWeight(.semibold)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(showsPrivate ? .purple : .accentColor)
        .navigationTitle(showsPrivate ? "Private Browsing" : "Tabs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close All", role: .destructive) { confirmsCloseAll = true }
                    .disabled(sessionTabs.isEmpty)
            }
        }
        .confirmationDialog(
            showsPrivate ? "Close all private tabs?" : "Close all regular tabs?",
            isPresented: $confirmsCloseAll, titleVisibility: .visible
        ) {
            Button("Close All \(sessionTabs.count) Tabs", role: .destructive) {
                manager.closeAll(isPrivate: showsPrivate)
            }
        } message: {
            Text("All tabs in this browsing session will close, including tabs hidden by search. The other session is not affected. The final tab is replaced with a start page.")
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Tabs")
        .onAppear { showsPrivate = manager.selectedTab?.isPrivate ?? false }
        .onChange(of: showsPrivate) { _, _ in search = "" }
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserViewModel
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var previewHeight = 180.0
    @State private var preview: UIImage?
    @State private var previewUnavailable = false
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "TabPreview")

    private struct PreviewIdentity: Equatable {
        let url: URL?
        let loading: Bool
        let startPage: Bool
        let failed: Bool
        let foreground: Bool
    }

    private var previewIdentity: PreviewIdentity {
        PreviewIdentity(
            url: tab.currentURL, loading: tab.isLoading,
            startPage: tab.showingStartPage, failed: tab.navigationError != nil,
            foreground: scenePhase == .active
        )
    }

    private var title: String {
        if tab.showingStartPage { return "Start Page" }
        return tab.pageTitle.isEmpty ? (tab.restorableURL?.host() ?? "Untitled Page") : tab.pageTitle
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 0) {
                    previewContent
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                        .clipped()
                        .accessibilityHidden(true)

                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(tab.showingStartPage ? "Duo Browser" : (tab.restorableURL?.host() ?? tab.addressText))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(12)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(selected ? (tab.isPrivate ? Color.purple : Color.accentColor) : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 3 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title)")
            .accessibilityValue(selected ? "Selected tab" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("tab.select.\(tab.id.uuidString)")
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.65), in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(tab.pageTitle.isEmpty ? "tab" : tab.pageTitle)")
            .accessibilityIdentifier("tab.close.\(tab.id.uuidString)")
            .padding(4)
        }
        .task(id: previewIdentity) { await capturePreview() }
        .onDisappear { preview = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { preview = nil }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if scenePhase != .active {
            placeholder("Tab Preview Hidden", icon: "eye.slash")
        } else if tab.showingStartPage {
            placeholder("Duo Browser", icon: tab.isPrivate ? "hand.raised.fill" : "globe")
        } else if tab.navigationError != nil {
            placeholder("Unable to Open Page", icon: "network.slash")
        } else if let preview {
            GeometryReader { geometry in
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .clipped()
            }
        } else if tab.isLoading {
            ProgressView("Loading Page")
        } else if previewUnavailable {
            placeholder("Preview Unavailable", icon: "doc.text")
        } else {
            ProgressView("Preparing Preview")
        }
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.tint)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
    }

    @MainActor
    private func capturePreview() async {
        preview = nil
        previewUnavailable = false
        guard scenePhase == .active, !tab.showingStartPage, !tab.isClosed,
              tab.navigationError == nil, !tab.isLoading else { return }
        let bounds = tab.webView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            previewUnavailable = true
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = 240
        configuration.rect = CGRect(
            x: bounds.minX, y: bounds.minY, width: bounds.width,
            height: min(bounds.height, bounds.width * 1.15)
        )
        do {
            let image = try await tab.webView.takeSnapshot(configuration: configuration)
            guard !Task.isCancelled, !tab.isClosed, scenePhase == .active else { return }
            preview = image
        } catch {
            guard !Task.isCancelled else { return }
            logger.notice("A tab preview could not be captured.")
            previewUnavailable = true
        }
    }
}
