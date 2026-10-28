import SwiftUI

struct BrowserAddressBar: View {
    @ObservedObject var model: BrowserViewModel
    @State private var address = ""
    @FocusState private var isFocused: Bool

    private var inactiveAddress: String {
        if model.showingStartPage { return "Search or enter website" }
        return model.navigationError?.url?.host()
            ?? model.currentURL?.host()
            ?? model.addressText
    }

    var body: some View {
        VStack(spacing: 4) {
            if !model.pageTitle.isEmpty, !model.showingStartPage {
                Text(model.pageTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Page title: \(model.pageTitle)")
            }
            HStack(spacing: 8) {
                if !model.showingStartPage {
                    Button {
                        model.showNotice(model.isSecure
                            ? "This page uses HTTPS and WebKit reports no insecure content. This does not verify that a website is trustworthy."
                            : "A fully secure connection is not confirmed for this page.")
                    } label: {
                        Image(systemName: model.isSecure ? "lock.fill" : "exclamationmark.triangle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(model.isSecure ? "HTTPS connection information" : "Connection information")
                }

                TextField("Search or enter website", text: $address)
                    .textContentType(.URL)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isFocused)
                    .multilineTextAlignment(isFocused ? .leading : .center)
                    .accessibilityLabel("Address and search")
                    .frame(minHeight: 44)
                    .onSubmit {
                        model.navigate(address)
                        isFocused = false
                    }

                if isFocused {
                    Button {
                        address = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Clear address")
                } else if !model.showingStartPage {
                    Button {
                        if model.isLoading { model.stop() } else { model.reload() }
                    } label: {
                        Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(model.isLoading ? "Stop loading" : "Reload page")
                }
            }
            .padding(.leading, model.showingStartPage ? 12 : 0)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
        .onAppear { updateAddress() }
        .onChange(of: model.addressText) { _, _ in
            if !isFocused { updateAddress() }
        }
        .onChange(of: isFocused) { _, focused in
            address = focused ? model.addressText : inactiveAddress
        }
    }

    private func updateAddress() {
        address = model.showingStartPage ? "" : inactiveAddress
    }
}
