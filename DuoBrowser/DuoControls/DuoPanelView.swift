import SwiftUI

struct DuoPanelView: View {
    @ObservedObject var bridge: DuoBridge
    @State private var confirmation: DuoControl?
    @State private var confirmationValue: JSONValue?

    var body: some View {
        if let panel = bridge.panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Duo Controls from \(bridge.origin ?? "website")")
                            .font(.caption.bold())
                        if let title = panel.title { Text(title).font(.caption) }
                    }
                    Spacer()
                    Button("Browser", systemImage: "safari") {
                        bridge.browserControlsVisible = true
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("duo.browser-controls")
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(panel.controls) { control in
                            controlView(control)
                                .disabled(control.enabled == false)
                                .accessibilityLabel(control.accessibilityLabel ?? control.label)
                                .accessibilityIdentifier("duo.control.\(control.id)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
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
        }
    }

    @ViewBuilder
    private func controlView(_ control: DuoControl) -> some View {
        switch control.type {
        case .button, .primary:
            if control.type == .primary {
                Button { activate(control) } label: { label(control) }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            } else {
                Button { activate(control) } label: { label(control) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        case .toggle:
            Toggle(isOn: Binding(
                get: { control.value == .bool(true) },
                set: { activate(control, value: .bool($0)) }
            )) { label(control) }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        case .segmented:
            VStack(alignment: .leading) {
                Text(control.label).font(.caption)
                Picker(control.label, selection: Binding(
                    get: {
                        if case .string(let value) = control.value { return value }
                        return control.options?.first?.id ?? ""
                    },
                    set: { activate(control, value: .string($0)) }
                )) {
                    ForEach(control.options ?? []) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }
            .frame(minWidth: 240, minHeight: 44)
        case .menu:
            Menu {
                ForEach(control.options ?? []) { option in
                    Button(option.label) { activate(control, value: .string(option.id)) }
                }
            } label: { label(control) }
                .frame(minHeight: 44)
        case .spacer:
            Spacer().frame(width: 16)
        }
    }

    private func label(_ control: DuoControl) -> some View {
        HStack {
            if let icon = control.icon { Image(systemName: icon) }
            Text(control.label)
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
