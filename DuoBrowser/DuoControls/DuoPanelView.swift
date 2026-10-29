import SwiftUI

struct DuoPanelView: View {
    @ObservedObject var bridge: DuoBridge
    let canGoBack: Bool
    let isLoading: Bool
    let goBack: () -> Void
    let refreshOrStop: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmation: DuoControl?
    @State private var confirmationValue: JSONValue?

    var body: some View {
        if let panel = bridge.panel {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duo Controls")
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text("From \(bridge.origin ?? "website")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        Button {
                            bridge.browserControlsVisible = true
                            bridge.cancelPendingCapabilities()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Hide Duo Controls")
                        .accessibilityIdentifier("duo.browser-controls")
                    }
                    HStack(spacing: 12) {
                        Button(action: goBack) {
                            Label("Back", systemImage: "chevron.backward")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(!canGoBack)
                        .accessibilityIdentifier("duo.browser.back")
                        Button(action: refreshOrStop) {
                            Label(isLoading ? "Stop" : "Refresh",
                                  systemImage: isLoading ? "xmark" : "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("duo.browser.refresh")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let title = panel.title {
                            Text(title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .accessibilityIdentifier("duo.controls.list")
                        ForEach(panel.controls) { control in
                            controlView(control)
                                .disabled(control.enabled == false)
                                .accessibilityLabel(control.accessibilityLabel ?? control.label)
                                .accessibilityIdentifier("duo.control.\(control.id)")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .tint(accent(panel.accent))
            .confirmationDialog(
                "Confirm Website Action",
                isPresented: Binding(
                    get: { confirmation != nil },
                    set: { if !$0 { confirmation = nil; confirmationValue = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let control = confirmation {
                    Button(control.label) {
                        bridge.activate(control, value: confirmationValue)
                        confirmation = nil
                        confirmationValue = nil
                    }
                }
                Button("Cancel", role: .cancel) { confirmation = nil; confirmationValue = nil }
            } message: {
                Text("This action comes from \(bridge.origin ?? "the website"), not from iOS.")
            }
            .onChange(of: bridge.panel) { _, _ in
                confirmation = nil
                confirmationValue = nil
            }
        }
    }

    @ViewBuilder
    private func controlView(_ control: DuoControl) -> some View {
        switch control.type {
        case .button, .primary:
            if control.type == .primary {
                Button { activate(control) } label: { actionLabel(control) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { activate(control) } label: { actionLabel(control) }
                    .buttonStyle(.bordered)
            }
        case .toggle:
            Toggle(isOn: Binding(
                get: { control.value == .bool(true) },
                set: { activate(control, value: .bool($0)) }
            )) { label(control) }
                .frame(minHeight: 52)
                .padding(.horizontal, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case .segmented:
            VStack(alignment: .leading, spacing: 8) {
                Text(control.label).font(.subheadline.weight(.semibold))
                if dynamicTypeSize.isAccessibilitySize {
                    optionPicker(control).pickerStyle(.menu)
                } else {
                    optionPicker(control).pickerStyle(.segmented)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        case .menu:
            Menu {
                ForEach(control.options ?? []) { option in
                    Button(option.label) { activate(control, value: .string(option.id)) }
                }
            } label: {
                HStack {
                    label(control)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption)
                }
                .frame(minHeight: 52)
                .padding(.horizontal, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        case .spacer:
            Color.clear.frame(height: 8).accessibilityHidden(true)
        }
    }

    private func optionPicker(_ control: DuoControl) -> some View {
        Picker(control.label, selection: Binding(
            get: {
                if case .string(let value) = control.value { return value }
                return control.options?.first?.id ?? ""
            },
            set: { activate(control, value: .string($0)) }
        )) {
            ForEach(control.options ?? []) { Text($0.label).tag($0.id) }
        }
    }

    private func actionLabel(_ control: DuoControl) -> some View {
        label(control)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func label(_ control: DuoControl) -> some View {
        HStack(spacing: 10) {
            if let icon = control.icon { Image(systemName: icon) }
            Text(control.label)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let badge = control.badge {
                Text(badge).font(.caption.bold()).padding(4).background(.quaternary, in: Capsule())
            }
        }
    }

    private func activate(_ control: DuoControl, value: JSONValue? = nil) {
        if control.requiresConfirmation == true {
            confirmationValue = value
            confirmation = control
        } else {
            bridge.activate(control, value: value)
        }
    }

    private func accent(_ value: String?) -> Color {
        switch value {
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "pink": .pink
        default: .blue
        }
    }
}
