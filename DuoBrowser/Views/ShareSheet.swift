import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var completion: (@MainActor () -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "browser.share"
        let completion = completion
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in completion?() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
