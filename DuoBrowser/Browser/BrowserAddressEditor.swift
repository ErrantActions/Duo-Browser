import SwiftUI

struct BrowserAddressEditor: View {
    @Binding var address: String
    let searchProvider: SearchProvider
    var compact = false
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        addressInput
                        Button(action: submitAddress) {
                            Image(systemName: "arrow.right.circle.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(isEmpty)
                        .accessibilityLabel("Go")
                        .accessibilityIdentifier("browser.address.bubble.go")
                    }
                    validation
                }
                .buttonStyle(.borderless)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .accessibilityIdentifier("browser.address.bubble")
                .accessibilityAction(.escape, cancel)
            } else {
                fullEditor
            }
        }
        .task { isFocused = true }
        .onChange(of: address) { _, _ in validationMessage = nil }
    }

    private var isEmpty: Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addressInput: some View {
        HStack(spacing: 0) {
            TextField("Search or enter website", text: $address)
                .textContentType(.URL)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFocused)
                .frame(minHeight: 44)
                .accessibilityLabel("Address and search")
                .accessibilityIdentifier(compact ? "browser.address.bubble.field" : "browser.address.editor")
                .onSubmit(submitAddress)
            Button {
                address = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Clear address")
        }
    }

    @ViewBuilder
    private var validation: some View {
        if let validationMessage {
            Text(validationMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(compact ? 3 : nil)
                .accessibilityIdentifier("browser.address.validation")
        }
    }

    private var fullEditor: some View {
        NavigationStack {
            Form {
                Section("Address or Search") {
                    addressInput
                    validation
                }
            }
            .navigationTitle("Address and Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go", action: submitAddress)
                        .disabled(isEmpty)
                }
            }
        }
    }

    private func submitAddress() {
        switch URLNormalizer.resolve(address, searchProvider: searchProvider) {
        case .empty:
            validationMessage = "Enter a website address or a search phrase."
        case .invalid(let message):
            validationMessage = message
        case .website, .search, .external:
            isFocused = false
            submit(address)
        }
    }
}
