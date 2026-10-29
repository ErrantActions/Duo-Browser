import OSLog
import SwiftUI
import WebKit

enum ScannerInputError: LocalizedError {
    case unavailable(String), changedPage

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .changedPage: "The page or scan target changed. Select the field and scan again."
        }
    }
}

@MainActor
enum ScannerInput {
    static let world = WKContentWorld.world(name: "DuoScannerInput")

    static func script() throws -> String {
        guard let url = Bundle.main.url(forResource: "ScannerInput", withExtension: "js") else {
            throw ScannerInputError.unavailable("The scanner input helper is missing from this build.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func install(on webView: WKWebView) throws {
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: try script(), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world
        ))
    }

    static func call(on webView: WKWebView, arguments: [String: Any]) async throws -> Any? {
        try await webView.callAsyncJavaScript("return " + script(), arguments: arguments, in: nil, contentWorld: world)
    }

    static func clear(on webView: WKWebView, token: String) async {
        do {
            let result = try await call(on: webView, arguments: ["mode": "clear", "token": token])
            if result as? Bool != true {
                Logger(subsystem: "com.duobrowser.app", category: "ScannerInput").error("Scanner target cleanup was not confirmed.")
            }
        } catch {
            Logger(subsystem: "com.duobrowser.app", category: "ScannerInput").error("Scanner target cleanup failed: code \((error as NSError).code)")
        }
    }

    static func blockedReason(for model: BrowserViewModel) -> String? {
        if model.isClosed || model.showingStartPage || model.navigationError != nil { return "Open a webpage and select a text field first." }
        if model.webView.isLoading { return "Wait for the page to finish loading." }
        guard let origin = DuoOrigin.canonical(model.webView.url), origin == "duo-demo" || model.isSecure else {
            return "Scanner input requires a verified HTTPS page or the DuoKit demo."
        }
        return nil
    }
}

struct ScannerInputView: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var library: BrowserLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var scanning = false
    @State private var working = false
    @State private var error: String?
    @State private var operation = UUID()
    @State private var token: String?
    @State private var source: URL?
    @State private var navigationID: UUID?
    @State private var scanPreferences = ScannerPreferences()
    @State private var deadline: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "ScannerInput")

    private var preferences: Binding<ScannerPreferences> {
        Binding(get: { library.settings.scanner }, set: {
            var settings = library.settings
            settings.scanner = $0
            library.updateSettings(settings)
        })
    }

    var body: some View {
        ZStack {
            if scanning {
                ScannerView(preferences: scanPreferences, complete: finishScan)
            } else {
                NavigationStack {
                    Form {
                        Section {
                            Text("Select a text field on the page before opening this tool. Scanned text goes only into that field; it is not saved by Duo.")
                            if let reason = ScannerInput.blockedReason(for: model) { Text(reason).foregroundStyle(.secondary) }
                            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("scanner.input.error") }
                            Button("Start Scanning", systemImage: "barcode.viewfinder") {
                                Task { await start() }
                            }
                            .disabled(working || ScannerInput.blockedReason(for: model) != nil)
                            .accessibilityIdentifier("scanner.input.start")
                            if working { ProgressView("Preparing Scanner") }
                        }
                        ScannerSettingsSection(preferences: preferences)
                    }
                    .navigationTitle("Scan Into Field")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    }
                }
            }
        }
        .onChange(of: model.navigationID) { _, _ in
            cancel(nil)
            logger.info("Scanner closed after page navigation.")
            dismiss()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancel("Scanning stopped because Duo went into the background. Start a new scan to continue.") }
        }
        .onDisappear { cancel(nil) }
    }

    private func start() async {
        error = nil
        guard scenePhase == .active, let url = model.webView.url,
              ScannerInput.blockedReason(for: model) == nil else {
            error = ScannerInput.blockedReason(for: model) ?? "Bring Duo to the foreground before scanning."
            return
        }
        let id = UUID()
        operation = id
        beginDeadline(id)
        working = true
        let generation = model.navigationID
        do {
            let result = try await ScannerInput.call(on: model.webView, arguments: ["mode": "capture"])
            guard operation == id, scenePhase == .active, !model.isClosed,
                  generation == model.navigationID, url == model.webView.url else {
                if let captured = result as? String { await ScannerInput.clear(on: model.webView, token: captured) }
                throw ScannerInputError.changedPage
            }
            guard let result = result as? String, UUID(uuidString: result) != nil else { throw ScannerInputError.changedPage }
            token = result
            source = url
            navigationID = generation
            scanPreferences = library.settings.scanner
            deadline?.cancel()
            deadline = nil
            working = false
            deadline?.cancel()
            deadline = nil
            scanning = true
        } catch {
            guard operation == id else { return }
            working = false
            report(error, fallback: "Select an editable, non-sensitive text field on the page, then try again.")
        }
    }

    private func finishScan(_ outcome: ScannerOutcome) {
        scanning = false
        switch outcome {
        case .cancelled: cancel(nil)
        case .failure(let message): cancel(message)
        case .scanned(let value, _):
            let id = operation
            working = true
            beginDeadline(id)
            Task { @MainActor in
                defer {
                    if operation == id {
                        working = false
                        deadline?.cancel()
                        deadline = nil
                    }
                }
                guard operation == id, scenePhase == .active, !model.isClosed, model.isShowingScanner,
                      navigationID == model.navigationID, let source, source == model.webView.url, let token,
                      !value.isEmpty, value.utf8.count <= 4096 else {
                    cancel(ScannerInputError.changedPage.localizedDescription)
                    return
                }
                self.token = nil
                do {
                    let result = try await ScannerInput.call(on: model.webView, arguments: [
                        "mode": "apply", "token": token, "sourceURL": source.absoluteString, "value": value,
                        "expiresAt": Date().timeIntervalSince1970 * 1000 + 5000,
                        "insertion": scanPreferences.insertion == .selection ? "selection" : (scanPreferences.insertion == .replace ? "replace" : "append"),
                        "suffix": scanPreferences.suffix == .none ? "none" : (scanPreferences.suffix == .enter ? "enter" : "submit")
                    ])
                    guard operation == id else { return }
                    guard result as? Bool == true else { throw ScannerInputError.changedPage }
                    dismiss()
                } catch {
                    guard operation == id else { return }
                    report(error, fallback: "The field rejected input, changed, or does not support these settings. Check the page before retrying.")
                }
            }
        }
    }

    private func cancel(_ message: String?) {
        deadline?.cancel()
        deadline = nil
        operation = UUID()
        if let token {
            Task { await ScannerInput.clear(on: model.webView, token: token) }
        }
        token = nil
        source = nil
        navigationID = nil
        working = false
        scanning = false
        if let message { error = message }
    }

    private func beginDeadline(_ id: UUID) {
        deadline?.cancel()
        deadline = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(15))
                guard operation == id else { return }
                cancel("Scanner input timed out. Check the page before trying again; do not repeat a submission without checking its result.")
            } catch is CancellationError {
                return
            } catch {
                logger.error("Scanner deadline interrupted: code \((error as NSError).code)")
                cancel("Scanner input was interrupted. Check the page before trying again.")
            }
        }
    }

    private func report(_ failure: Error, fallback: String) {
        logger.error("Scanner input failed: code \((failure as NSError).code)")
        error = (failure as? ScannerInputError)?.localizedDescription ?? fallback
    }
}
