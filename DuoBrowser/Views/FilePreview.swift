import QuickLook
import SwiftUI

struct FilePreview: UIViewControllerRepresentable, Identifiable {
    let id = UUID()
    let url: URL
    let title: String

    static func canPreview(_ url: URL) -> Bool {
        QLPreviewController.canPreview(url as NSURL)
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url, title: title) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.item.previewItemURL != url
                || context.coordinator.item.previewItemTitle != title else { return }
        context.coordinator.item = PreviewItem(url: url, title: title)
        controller.reloadData()
    }

    final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL, title: String) {
            previewItemURL = url
            previewItemTitle = title
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: PreviewItem

        init(url: URL, title: String) {
            item = PreviewItem(url: url, title: title)
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            item
        }
    }
}
