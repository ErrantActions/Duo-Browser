import SwiftUI

struct BrowserAddressEditor: View {
    @Binding var address: String
    let searchProvider: SearchProvider
    let connectedExtension: CGFloat
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
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
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.regularMaterial)
                .padding(.trailing, -connectedExtension)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                .padding(.trailing, -connectedExtension)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, cancel)
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
                .accessibilityIdentifier("browser.address.bubble.field")
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
                .lineLimit(3)
                .accessibilityIdentifier("browser.address.validation")
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
