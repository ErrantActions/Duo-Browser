import SwiftUI

@available(iOS 27.1, *)
struct DuoNativeToolbar<Content: View>: View {
    @ObservedObject var model: BrowserViewModel
    let openAllControls: () -> Void
    let content: Content

    init(
        model: BrowserViewModel,
        openAllControls: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.openAllControls = openAllControls
        self.content = content()
    }

    private var activePanel: DuoPanel? {
        model.bridge.browserControlsVisible ? nil : model.bridge.panel
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbarVisibility(activePanel == nil ? .hidden : .visible, for: .navigationBar, .bottomBar)
                .toolbar {
                    if let panel = activePanel {
                        ToolbarItem(placement: .principal) {
                            Text("Controls from \(model.bridge.origin ?? "website")")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .axisBehavior(.horizontalOnly)

                        ToolbarItemGroup(placement: .bottomBar) {
                            Button(action: model.goBack) {
                                Label("Back", systemImage: "chevron.backward")
                            }
                            .disabled(!model.canGoBack)
                            .accessibilityIdentifier("duo.browser.back")
                            Button {
                                if model.isLoading { model.stop() } else { model.reload() }
                            } label: {
                                Label(model.isLoading ? "Stop" : "Refresh",
                                      systemImage: model.isLoading ? "xmark" : "arrow.clockwise")
                            }
                            .accessibilityIdentifier("duo.browser.refresh")

                            ForEach(panel.toolbarControls) { control in
                                DuoNativeToolbarControl(bridge: model.bridge, control: control)
                            }
                            Button(action: openAllControls) {
                                Label("All Website Controls", systemImage: "slider.horizontal.3")
                            }
                            .accessibilityIdentifier("duo.controls.all")
                        }
                        .axisBehavior(.verticalPreferred)
                    }
                }
        }
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
