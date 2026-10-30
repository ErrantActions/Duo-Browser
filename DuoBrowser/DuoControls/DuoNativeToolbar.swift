import SwiftUI

@available(iOS 27.1, *)
struct DuoNativeToolbar<Content: View>: View {
    let model: BrowserViewModel
    let manager: BrowserTabManager
    let openAllControls: () -> Void
    let addressExpanded: Bool
    let openAddress: () -> Void
    let share: () -> Void
    let present: (BrowserSheet) -> Void
    let content: (Bool, CGRect) -> Content

    init(
        model: BrowserViewModel, manager: BrowserTabManager,
        openAllControls: @escaping () -> Void,
        addressExpanded: Bool,
        openAddress: @escaping () -> Void,
        share: @escaping () -> Void,
        present: @escaping (BrowserSheet) -> Void,
        @ViewBuilder content: @escaping (Bool, CGRect) -> Content
    ) {
        self.model = model
        self.manager = manager
        self.openAllControls = openAllControls
        self.addressExpanded = addressExpanded
        self.openAddress = openAddress
        self.share = share
        self.present = present
        self.content = content
    }

    var body: some View {
        NavigationStack {
            DuoNativeToolbarContent(
                model: model, manager: manager, openAllControls: openAllControls,
                addressExpanded: addressExpanded,
                openAddress: openAddress, share: share, present: present, content: content
            )
        }
    }
}

@available(iOS 27.1, *)
private struct DuoNativeToolbarContent<Content: View>: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var manager: BrowserTabManager
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @State private var addressFrame = CGRect.zero
    let openAllControls: () -> Void
    let addressExpanded: Bool
    let openAddress: () -> Void
    let share: () -> Void
    let present: (BrowserSheet) -> Void
    let content: (Bool, CGRect) -> Content

    private var activePanel: DuoPanel? {
        model.bridge.browserControlsVisible ? nil : model.bridge.panel
    }

    private var detectedNavigation: SiteNavigationSnapshot? {
        guard activePanel == nil, !model.bridge.browserControlsVisible, !model.siteNavigation.toolbarLinks.isEmpty else { return nil }
        return model.siteNavigation.visibleSnapshot
    }

    private var usesVerticalBar: Bool { verticalEdge != nil }

    private var addressTitle: String {
        if model.showingStartPage { return "Search" }
        return model.navigationError?.url?.host() ?? model.currentURL?.host()
            ?? URL(string: model.addressText)?.host() ?? model.bridge.origin ?? "Address"
    }

    private var addressValue: String {
        let connection = model.showingStartPage ? "" : (model.isSecure ? ", HTTPS" : ", Connection not verified")
        return addressTitle + connection + (model.isPrivate ? ", Private Browsing" : "")
    }

    var body: some View {
        content(usesVerticalBar, addressFrame)
            .background {
                Color(uiColor: model.browserBackgroundColor)
                    .ignoresSafeArea(.container)
                    .allowsHitTesting(false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(usesVerticalBar ? .hidden : .automatic,
                                        for: .navigationBar, .bottomBar)
            .toolbarVisibility(usesVerticalBar || activePanel != nil || detectedNavigation != nil ? .visible : .hidden,
                               for: .navigationBar, .bottomBar)
            .toolbar {
                if usesVerticalBar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button(action: model.goBack) {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .disabled(addressExpanded || (!model.canGoBack && !(model.showingStartPage && model.currentURL != nil)))
                        .accessibilityIdentifier("duo.browser.back")
                        Button {
                            if model.isLoading { model.stop() } else { model.reload() }
                        } label: {
                            Label(model.isLoading ? "Stop" : "Refresh",
                                  systemImage: model.isLoading ? "xmark" : "arrow.clockwise")
                        }
                        .disabled(addressExpanded)
                        .accessibilityIdentifier("duo.browser.refresh")
                    }
                    .axisBehavior(.verticalPreferred)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openAddress) {
                            VStack(spacing: 2) {
                                if model.isLoading {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: model.isPrivate ? "hand.raised" : (model.isSecure ? "lock" : "globe"))
                                }
                                Text("URL")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("URL")
                        .accessibilityValue(addressValue)
                        .accessibilityHint(addressExpanded
                            ? "Close the address bubble without navigating"
                            : "Expand an address and search bubble")
                        .accessibilityIdentifier("browser.address.open")
                        .onGeometryChange(for: CGRect.self) { geometry in
                            geometry.frame(in: .global)
                        } action: { addressFrame = $0 }
                    }
                    .axisBehavior(.verticalPreferred)
                    .sharedBackgroundVisibility(addressExpanded ? .hidden : .automatic)
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if AskDuoModel.isVisible {
                            Button { present(.assistant) } label: {
                                Label("Ask Duo", systemImage: "sparkles")
                            }
                            .labelStyle(.iconOnly)
                            .disabled(addressExpanded)
                            .accessibilityHint("Chat with Apple Intelligence. Page access requires your approval.")
                            .accessibilityIdentifier("browser.askduo")
                        }
                        Button { present(.tabs) } label: {
                            Label("Tabs", systemImage: "square.on.square")
                        }
                        .disabled(addressExpanded)
                        .accessibilityLabel("Tabs, \(manager.tabs.count) open")
                        .accessibilityValue("\(manager.tabs.count)")
                        .accessibilityIdentifier("browser.tabs")
                        BrowserToolbar(
                            model: model, manager: manager, share: share,
                            present: present, menuOnly: true
                        )
                        .disabled(addressExpanded)
                    }
                    .axisBehavior(.verticalPreferred)
                }
                if let panel = activePanel {
                    if !usesVerticalBar {
                        ToolbarItem(placement: .principal) {
                            Text("Controls from \(model.bridge.origin ?? "website")")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .axisBehavior(.horizontalOnly)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        ForEach(panel.toolbarControls) { control in
                            DuoNativeToolbarControl(bridge: model.bridge, control: control)
                                .disabled(addressExpanded)
                        }
                        Button(action: openAllControls) {
                            Label("All Website Controls", systemImage: "slider.horizontal.3")
                        }
                        .disabled(addressExpanded)
                        .accessibilityIdentifier("duo.controls.all")
                    }
                    .axisBehavior(.verticalPreferred)
                } else if let detectedNavigation {
                    if !usesVerticalBar {
                        ToolbarItem(placement: .principal) {
                            Text("Navigation from \(detectedNavigation.context.url.host ?? "DuoKit Demo")")
                                .font(.caption).lineLimit(1)
                        }
                        .axisBehavior(.horizontalOnly)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        ForEach(Array(model.siteNavigation.toolbarLinks.enumerated()), id: \.element.id) { index, link in
                            DetectedNavigationToolbarControl(
                                navigation: model.siteNavigation, link: link, index: index,
                                origin: detectedNavigation.context.url.host ?? "DuoKit Demo",
                                addressExpanded: addressExpanded
                            )
                        }
                    }
                    .axisBehavior(.verticalPreferred)
                }
            }
    }
}

@available(iOS 27.1, *)
private struct DetectedNavigationToolbarControl: View {
    @ObservedObject var navigation: SiteNavigationModel
    let link: SiteNavigationLink
    let index: Int
    let origin: String
    let addressExpanded: Bool

    var body: some View {
        Button { navigation.activate(link) } label: {
            Label { Text(verbatim: link.label) } icon: { Image(systemName: link.icon) }
        }
        .labelStyle(.iconOnly)
        .help(link.label)
        .disabled(addressExpanded || navigation.isOpening)
        .accessibilityLabel(link.label)
        .accessibilityHint("Detected website link from \(origin)")
        .accessibilityIdentifier("site.navigation.quick.\(index)")
    }
}

@available(iOS 27.1, *)
private struct DuoNativeToolbarControl: View {
    @ObservedObject var bridge: DuoBridge
    let control: DuoControl
    @State private var confirmsActivation = false
    @State private var pendingValue: JSONValue?

    var body: some View {
        content
            .labelStyle(.iconOnly)
            .disabled(control.enabled == false)
            .accessibilityLabel(control.accessibilityLabel ?? control.label)
            .accessibilityValue(control.badge ?? "")
            .accessibilityHint("Website action from \(bridge.origin ?? "the current site")")
            .accessibilityIdentifier("duo.control.\(control.id)")
            .confirmationDialog("Confirm Website Action", isPresented: $confirmsActivation, titleVisibility: .visible) {
                Button(control.label) { bridge.activate(control, value: pendingValue) }
                Button("Cancel", role: .cancel) { pendingValue = nil }
            } message: {
                Text("This action comes from \(bridge.origin ?? "the website"), not from iOS.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch control.type {
        case .button, .primary:
            Button { activate() } label: { label }
        case .toggle:
            Toggle(isOn: Binding(
                get: { control.value == .bool(true) },
                set: { activate(value: .bool($0)) }
            )) { label }
            .toggleStyle(.button)
        case .segmented, .menu:
            Menu {
                ForEach(control.options ?? []) { option in
                    Button(option.label) { activate(value: .string(option.id)) }
                }
            } label: { label }
        case .spacer:
            EmptyView()
        }
    }

    private var label: some View {
        Label(control.label, systemImage: control.icon ?? fallbackIcon)
    }

    private var fallbackIcon: String {
        switch control.type {
        case .toggle: "switch.2"
        case .segmented, .menu: "list.bullet"
        default: "circle"
        }
    }

    private func activate(value: JSONValue? = nil) {
        if control.requiresConfirmation == true {
            pendingValue = value
            confirmsActivation = true
        } else {
            bridge.activate(control, value: value)
        }
    }
}
