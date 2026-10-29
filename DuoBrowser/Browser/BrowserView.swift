import SwiftUI

enum BrowserSheet: String, Identifiable {
    case tabs, bookmarks, history, readingList, downloads, settings, permissions, bookmark, recentlyClosedTabs
    var id: String { rawValue }
}

struct BrowserView: View {
    @StateObject private var library: BrowserLibrary
    @StateObject private var manager: BrowserTabManager
    @State private var sheet: BrowserSheet?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let library = BrowserLibrary()
        _library = StateObject(wrappedValue: library)
        _manager = StateObject(wrappedValue: BrowserTabManager(library: library))
    }

    var body: some View {
        Group {
            if let tab = manager.selectedTab {
                BrowserTabView(model: tab, manager: manager, present: present)
                    .id(tab.id)
            } else {
                ProgressView(manager.isClearingData ? "Clearing Browsing Data" : "Opening Browser")
            }
        }
        .preferredColorScheme(colorScheme)
        .sheet(item: $sheet, onDismiss: { manager.selectedTab?.isActive = true }) { selection in
            NavigationStack {
                sheetContent(selection)
                    .toolbar {
                        if selection != .tabs && selection != .bookmark {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { sheet = nil }
                                    .disabled(manager.isClearingData)
                            }
                        }
                    }
            }
            .interactiveDismissDisabled(manager.isClearingData)
            .alert("Duo Browser", isPresented: statusAlert(inSheet: true)) {
                Button("OK", action: clearStatus)
            } message: {
                Text(statusMessage)
            }
        }
        .alert("Duo Browser", isPresented: statusAlert(inSheet: false)) {
            Button("OK", action: clearStatus)
        } message: {
            Text(statusMessage)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, sheet == nil {
                manager.selectedTab?.isActive = true
            } else if phase == .background {
                manager.selectedTab?.deactivate()
                manager.saveSession()
            }
        }
        .onChange(of: manager.selectedID) { _, _ in
            if sheet != nil { manager.selectedTab?.deactivate() }
        }
    }

    @ViewBuilder
    private func sheetContent(_ selection: BrowserSheet) -> some View {
        switch selection {
        case .tabs:
            TabOverviewView(
                manager: manager, done: { sheet = nil },
                showRecentlyClosed: { sheet = .recentlyClosedTabs }
            )
        case .bookmarks: BookmarksView(library: library, open: open, openInNewTab: openInNewTab)
        case .history: HistoryView(library: library, open: open, openInNewTab: openInNewTab)
        case .readingList: ReadingListView(library: library, open: open, openInNewTab: openInNewTab)
        case .recentlyClosedTabs: RecentlyClosedTabsView(manager: manager) { sheet = nil }
        case .downloads: DownloadsView(manager: manager.downloads)
        case .settings: BrowserSettingsView(library: library, manager: manager)
        case .permissions: SitePermissionsView(library: library, manager: manager)
        case .bookmark:
            if let tab = manager.selectedTab, let url = tab.shareURL {
                BookmarkEditor(
                    library: library,
                    bookmark: Bookmark(title: tab.pageTitle, url: url)
                ) { sheet = nil }
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch library.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func present(_ selection: BrowserSheet) {
        manager.selectedTab?.deactivate()
        sheet = selection
    }

    private func open(_ url: URL) {
        sheet = nil
        manager.selectedTab?.isActive = true
        manager.selectedTab?.load(url)
    }

    private func openInNewTab(_ url: URL) {
        let isPrivate = manager.selectedTab?.isPrivate ?? false
        guard let tab = manager.addTab(url: url, isPrivate: isPrivate) else { return }
        sheet = nil
        tab.isActive = true
    }

    private var statusMessage: String { library.storageError ?? manager.notice ?? "" }

    private func statusAlert(inSheet: Bool) -> Binding<Bool> {
        Binding(
            get: { (sheet != nil) == inSheet && (library.storageError != nil || manager.notice != nil) },
            set: { if !$0 { clearStatus() } }
        )
    }

    private func clearStatus() {
        library.storageError = nil
        manager.notice = nil
    }
}

private struct BrowserTabView: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var manager: BrowserTabManager
    let present: (BrowserSheet) -> Void
    @State private var sharedPage: SharedPage?
    @State private var showsCompactControls = false
    @State private var showsAddressBubble = false
    @State private var showsAddressEditor = false
    @State private var addressDraft = ""
    @State private var addressBubbleHeight: CGFloat = 60
    @State private var pendingAddress: String?
    @Environment(\.scenePhase) private var scenePhase

    private var showsSiteControls: Bool {
        model.bridge.panel != nil && !model.bridge.browserControlsVisible
    }

    private var isEditingAddress: Bool { showsAddressBubble || showsAddressEditor }

    var body: some View {
        Group {
            if #available(iOS 27.1, *) {
                DuoNativeToolbar(
                    model: model, manager: manager,
                    openAllControls: { showsCompactControls = true },
                    addressExpanded: showsAddressBubble,
                    openAddress: openAddress,
                    share: sharePage,
                    present: present
                ) { usesVerticalBar, addressFrame in
                    browserContent(showControlsButton: false, usesVerticalBar: usesVerticalBar, addressFrame: addressFrame)
                }
            } else {
                browserContent(showControlsButton: showsSiteControls)
            }
        }
        .onChange(of: showsSiteControls) { _, available in
            if !available { showsCompactControls = false }
        }
        .sheet(isPresented: $showsAddressEditor, onDismiss: completeAddressEditing) {
            BrowserAddressEditor(
                address: $addressDraft, searchProvider: model.library.settings.searchProvider,
                submit: {
                    pendingAddress = $0
                    showsAddressEditor = false
                },
                cancel: { showsAddressEditor = false }
            )
        }
        .sheet(isPresented: $showsCompactControls, onDismiss: model.bridge.cancelPendingCapabilities) {
            NavigationStack {
                siteControls
                    .navigationTitle("Website Controls")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsCompactControls = false }
                        }
                    }
            }
            .accessibilityIdentifier("duo.panel.sheet")
            .modifier(DuoCapabilityPresentation(bridge: model.bridge, enabled: showsCompactControls))
        }
        .modifier(DuoCapabilityPresentation(bridge: model.bridge, enabled: !showsCompactControls && !isEditingAddress))
        .sheet(item: $sharedPage, onDismiss: { model.isActive = true }) { ShareSheet(url: $0.url) }
        .sheet(item: $model.pageDialog, onDismiss: model.cancelPageDialog) { dialog in
            PageDialogView(dialog: dialog, complete: model.completePageDialog)
                .interactiveDismissDisabled()
        }
        .alert(item: $model.alert) { alert in
            switch alert.content {
            case .notice(let message):
                return Alert(title: Text("Duo Browser"), message: Text(message))
            case .openExternal(let url):
                return Alert(
                    title: Text("Open another app?"),
                    message: Text("This link uses \(url.scheme ?? "an external app"). Only continue if you trust the website."),
                    primaryButton: .default(Text("Open")) { model.openExternal(url) },
                    secondaryButton: .cancel()
                )
            }
        }
        .onChange(of: model.bridge.errorMessage) { _, message in
            if let message {
                model.showNotice(message)
                model.bridge.errorMessage = nil
            }
        }
        .onDisappear {
            if isEditingAddress {
                showsAddressBubble = false
                showsAddressEditor = false
                pendingAddress = nil
                addressDraft = ""
                model.endAddressEditing(isActive: false)
            }
        }
        .onChange(of: showsAddressBubble) { _, visible in
            if !visible && !showsAddressEditor { completeAddressEditing() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { showsAddressBubble = false }
        }
    }

    private func browserContent(
        showControlsButton: Bool, usesVerticalBar: Bool = false, addressFrame: CGRect = .zero
    ) -> some View {
        VStack(spacing: 0) {
            pageContent
            if !usesVerticalBar {
                browserChrome(showControlsButton: showControlsButton)
            }
        }
        .overlay {
            if showsAddressBubble && usesVerticalBar {
                GeometryReader { geometry in
                    BrowserAddressEditor(
                        address: $addressDraft, searchProvider: model.library.settings.searchProvider,
                        compact: true,
                        submit: {
                            pendingAddress = $0
                            showsAddressBubble = false
                        },
                        cancel: { showsAddressBubble = false }
                    )
                    .frame(width: max(0, min(360, geometry.size.width - 16)))
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        addressBubbleHeight = $0
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .offset(y: max(8, min(
                        geometry.size.height - addressBubbleHeight - 8,
                        addressFrame.midY - geometry.frame(in: .global).minY - 30
                    )))
                }
            }
        }
        .onChange(of: usesVerticalBar) { _, vertical in
            if !vertical { showsAddressBubble = false }
        }
    }

    private var pageContent: some View {
        ZStack {
            WebViewContainer(webView: model.webView)
                .accessibilityIdentifier("browser.webpage")
                .accessibilityHidden(model.showingStartPage || model.navigationError != nil)
                .allowsHitTesting(!model.showingStartPage && model.navigationError == nil)
            if model.showingStartPage {
                startPage
            } else if let error = model.navigationError {
                BrowserErrorView(error: error, retry: model.reload, goHome: model.goToStartPage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if showsAddressBubble {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showsAddressBubble = false }
            }
        }
    }

    private func browserChrome(showControlsButton: Bool) -> some View {
        VStack(spacing: 4) {
            if model.isPrivate {
                Label("Private Browsing", systemImage: "hand.raised.fill")
                    .font(.caption.bold())
            }
            if model.isLoading && !model.showingStartPage {
                ProgressView(value: model.estimatedProgress)
                    .accessibilityLabel("Page loading progress")
            }
            if showControlsButton {
                Button {
                    showsCompactControls = true
                } label: {
                    Label("Duo Controls", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Open this website's navigation and actions in a separate panel")
                .accessibilityIdentifier("duo.controls.open")
            }
            BrowserAddressBar(model: model)
            BrowserToolbar(
                model: model, manager: manager,
                share: sharePage,
                present: present
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(.bar)
        .accessibilityIdentifier("browser.bottom.chrome")
    }

    private func sharePage() {
        if let url = model.shareURL {
            model.deactivate()
            sharedPage = SharedPage(url: url)
        }
    }

    private func completeAddressEditing() {
        let address = pendingAddress
        pendingAddress = nil
        addressDraft = ""
        let selected = manager.selectedID == model.id && !model.isClosed
        model.endAddressEditing(isActive: selected && scenePhase == .active)
        guard selected else { return }
        if let address { model.navigate(address) }
    }

    private func openAddress() {
        if showsAddressBubble {
            showsAddressBubble = false
            showsAddressEditor = true
        } else {
            model.beginAddressEditing()
            addressDraft = model.addressText
            addressBubbleHeight = 60
            showsAddressBubble = true
        }
    }

    private var siteControls: some View {
        DuoPanelView(
            bridge: model.bridge, canGoBack: model.canGoBack, isLoading: model.isLoading,
            goBack: model.goBack,
            refreshOrStop: {
                if model.isLoading { model.stop() } else { model.reload() }
            }
        )
    }

    private var startPage: some View {
        BrowserStartPageView(
            library: model.library, isPrivate: model.isPrivate,
            open: model.load,
            openInNewTab: { url in manager.addTab(url: url, isPrivate: model.isPrivate) },
            showBookmarks: { present(.bookmarks) },
            showHistory: { present(.history) },
            showReadingList: { present(.readingList) },
            openDemo: model.loadDemo,
            openSettings: { present(.settings) }
        )
    }
}
