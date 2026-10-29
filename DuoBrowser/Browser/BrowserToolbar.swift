import SwiftUI

struct BrowserToolbar: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var manager: BrowserTabManager
    let share: () -> Void
    let present: (BrowserSheet) -> Void
    var menuOnly = false
    @State private var showsMenu = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        HStack {
            if !menuOnly {
            toolbarButton("Back", icon: "chevron.backward", action: model.goBack)
                .disabled(!model.canGoBack && !(model.showingStartPage && model.currentURL != nil))
            Spacer(minLength: 0)
            toolbarButton("Forward", icon: "chevron.forward", action: model.goForward)
                .disabled(!model.canGoForward || model.showingStartPage)
            Spacer(minLength: 0)
            toolbarButton("Share page", icon: "square.and.arrow.up", action: share)
                .disabled(model.shareURL == nil)
            Spacer(minLength: 0)
            Button { present(.tabs) } label: {
                ZStack {
                    Image(systemName: "square.on.square")
                    Text("\(manager.tabs.count)").font(.caption2.bold()).offset(y: 1)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Tabs, \(manager.tabs.count) open")
            .accessibilityValue("\(manager.tabs.count)")
            .accessibilityIdentifier("browser.tabs")
            Spacer(minLength: 0)
            }
            toolbarButton("Browser menu", icon: "ellipsis.circle") {
                model.deactivate()
                showsMenu = true
            }
        }
        .sheet(isPresented: $showsMenu, onDismiss: completeMenuAction) {
            NavigationStack {
                List {
                    Section {
                        menuAction("Ask Duo", icon: "sparkles") { present(.assistant) }
                            .accessibilityIdentifier("browser.askduo")
                    }
                    Section("Tabs") {
                        menuAction("Forward", icon: "chevron.forward", action: model.goForward)
                            .disabled(!model.canGoForward || model.showingStartPage)
                        menuAction("New Tab", icon: "plus") { manager.addTab() }
                        menuAction("New Private Tab", icon: "hand.raised") { manager.addTab(isPrivate: true) }
                        menuAction("Reopen Last Closed Tab", icon: "arrow.uturn.backward") {
                            if let tab = manager.recentlyClosedTabs.first { manager.reopen(tab.id) }
                        }
                        .disabled(manager.recentlyClosedTabs.isEmpty)
                        menuAction("Recently Closed Tabs", icon: "clock.arrow.circlepath") {
                            present(.recentlyClosedTabs)
                        }
                        menuAction("Start Page", icon: "house", action: model.goToStartPage)
                    }
                    Section("Library") {
                        menuAction("Bookmarks", icon: "book") { present(.bookmarks) }
                        menuAction("Add Bookmark", icon: "bookmark") { present(.bookmark) }
                            .disabled(model.shareURL == nil)
                        menuAction("History", icon: "clock") { present(.history) }
                        menuAction("Reading List", icon: "eyeglasses") { present(.readingList) }
                        menuAction("Add to Reading List", icon: "text.badge.plus") {
                            guard let url = model.shareURL else { return }
                            if model.library.addToReadingList(title: model.pageTitle, url: url) {
                                model.showNotice("Saved to Reading List.")
                            }
                        }
                        .disabled(model.shareURL == nil)
                        menuAction("Downloads", icon: "arrow.down.circle") { present(.downloads) }
                    }
                    Section("Duo") {
                        if model.bridge.panel != nil {
                            menuAction("Show Duo Panel", icon: "slider.horizontal.3") {
                                model.bridge.browserControlsVisible = false
                            }
                        }
                        menuAction("Duo Site Permissions", icon: "checkmark.shield") { present(.permissions) }
                        menuAction("DuoKit Demo", icon: "slider.horizontal.3", action: model.loadDemo)
                        menuAction("Settings", icon: "gearshape") { present(.settings) }
                    }
                    Section("Page") {
                        HStack {
                            Button {
                                model.setPageZoom(max(0.5, model.pageZoom - 0.25))
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Zoom out")
                            .disabled(model.pageZoom <= 0.5)
                            Spacer()
                            Button("\(Int((model.pageZoom * 100).rounded()))%") {
                                model.setPageZoom(1)
                            }
                            .frame(minHeight: 44)
                            .accessibilityLabel("Page zoom \(Int((model.pageZoom * 100).rounded())) percent. Reset to 100 percent")
                            Spacer()
                            Button {
                                model.setPageZoom(min(3, model.pageZoom + 0.25))
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Zoom in")
                            .disabled(model.pageZoom >= 3)
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.showingStartPage || model.navigationError != nil)
                        menuAction("Find on Page", icon: "doc.text.magnifyingglass", action: model.findInPage)
                            .disabled(model.showingStartPage || model.navigationError != nil)
                        menuAction("Share Page", icon: "square.and.arrow.up", action: share)
                            .disabled(model.shareURL == nil)
                        menuAction(
                            model.isLoading ? "Stop Loading" : "Reload",
                            icon: model.isLoading ? "xmark" : "arrow.clockwise"
                        ) {
                            if model.isLoading { model.stop() } else { model.reload() }
                        }
                        menuAction(
                            model.requestsDesktopSite ? "Request Mobile Site" : "Request Desktop Site",
                            icon: model.requestsDesktopSite ? "iphone" : "desktopcomputer",
                            action: model.toggleContentMode
                        )
                        menuAction("Page Information", icon: "info.circle") {
                            model.showNotice("\(model.pageTitle)\n\(model.addressText)\n\(model.isSecure ? "HTTPS; no insecure content reported by WebKit." : "A fully secure connection is not confirmed.")")
                        }
                    }
                }
                .accessibilityIdentifier("browser.menu.actions")
                .navigationTitle("Browser Menu")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close Menu") { showsMenu = false }
                    }
                }
            }
        }
    }

    private func toolbarButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(title)
    }

    private func menuAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon) {
            pendingAction = action
            showsMenu = false
        }
    }

    private func completeMenuAction() {
        let action = pendingAction
        pendingAction = nil
        if manager.selectedID == model.id { model.isActive = true }
        // Present another sheet only after the menu has finished dismissing.
        action?()
    }
}
