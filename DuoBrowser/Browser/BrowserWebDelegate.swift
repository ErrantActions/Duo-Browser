import UIKit
import WebKit

@MainActor
final class BrowserWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var owner: BrowserViewModel?

    @objc func refreshPage() {
        owner?.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        guard let owner, !owner.isClosed, let url = navigationAction.request.url else {
            decisionHandler(.cancel, preferences)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https"].contains(scheme) || url.absoluteString == "about:blank" {
            preferences.preferredContentMode = owner.requestsDesktopSite ? .desktop : .mobile
            if navigationAction.targetFrame?.isMainFrame == true {
                owner.rememberRequest(url)
            }
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
            return
        }
        if url.isFileURL, let demoURL = DuoOrigin.demoURL,
           url.deletingLastPathComponent() == demoURL.deletingLastPathComponent(),
           url.lastPathComponent == demoURL.lastPathComponent {
            decisionHandler(.allow, preferences)
            return
        }

        // Automatic redirects and iframes must not launch other applications.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.sourceFrame.isMainFrame,
           navigationAction.targetFrame?.isMainFrame != false {
            owner.requestExternalNavigation(url)
        } else if navigationAction.targetFrame?.isMainFrame != false {
            owner.showNotice("Duo Browser blocked an unsupported or automatic app-opening link.")
        }
        decisionHandler(.cancel, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let owner, !owner.isClosed else {
            decisionHandler(.cancel)
            return
        }
        guard navigationResponse.canShowMIMEType else {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        owner?.navigationWillStart()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.navigationDidFinish()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        owner?.navigationDidFail(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        owner?.navigationDidFail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        owner?.contentProcessDidTerminate()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if owner?.isClosed == false, navigationAction.targetFrame == nil {
            owner?.onNewWindow?(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        guard let owner, !owner.isClosed else { download.cancel { _ in }; return }
        owner.downloads.register(download, isPrivate: owner.isPrivate)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        guard let owner, !owner.isClosed else { download.cancel { _ in }; return }
        owner.downloads.register(download, isPrivate: owner.isPrivate)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard let owner, !owner.isClosed, owner.isActive, !owner.library.settings.denyWebsiteMedia else {
            decisionHandler(.deny)
            return
        }
        decisionHandler(.prompt)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard let owner else {
            completionHandler()
            return
        }
        owner.presentPageDialog(
            kind: .alert, website: dialogOrigin(frame), message: message
        ) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let owner else {
            completionHandler(false)
            return
        }
        owner.presentPageDialog(
            kind: .confirmation, website: dialogOrigin(frame), message: message
        ) { completionHandler($0 != nil) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard let owner else {
            completionHandler(nil)
            return
        }
        owner.presentPageDialog(
            kind: .prompt, website: dialogOrigin(frame),
            message: prompt, defaultText: defaultText ?? "",
            completion: completionHandler
        )
    }

    private func dialogOrigin(_ frame: WKFrameInfo) -> String {
        let origin = frame.securityOrigin
        guard !origin.host.isEmpty else { return "Webpage" }
        let port = origin.port == 0 ? "" : ":\(origin.port)"
        return "\(origin.protocol)://\(origin.host)\(port)"
    }
}
