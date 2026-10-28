import SwiftUI

struct BrowserErrorView: View {
    let error: BrowserNavigationError
    let retry: () -> Void
    let goHome: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "network.slash")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("Unable to Open Page")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(error.message)
                    .multilineTextAlignment(.center)
                if let url = error.url {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .disabled(error.url == nil)
                    .frame(minHeight: 44)
                Button("Go to Start Page", action: goHome)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
