import SwiftUI

struct BrowserAddressEditor: View {
    let searchProvider: SearchProvider
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var address: String
    @State private var validationMessage: String?
    @FocusState private var isFocused: Bool

    init(
        address: String, searchProvider: SearchProvider,
        submit: @escaping (String) -> Void, cancel: @escaping () -> Void
    ) {
        self.searchProvider = searchProvider
        self.submit = submit
        self.cancel = cancel
        _address = State(initialValue: address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Address or Search") {
                    HStack {
                        TextField("Search or enter website", text: $address)
                            .textContentType(.URL)
                            .keyboardType(.webSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($isFocused)
                            .accessibilityLabel("Address and search")
                            .accessibilityIdentifier("browser.address.editor")
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
                    if let validationMessage {
                        Text(validationMessage).foregroundStyle(.red)
                    }
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
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { isFocused = true }
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
