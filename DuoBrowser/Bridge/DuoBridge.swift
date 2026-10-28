import Combine
import Foundation
import OSLog
import WebKit

struct DuoPermissionRequest: Identifiable {
    enum Capability: String {
        case controls = "Duo Controls"
        case scanner = "Scanner"
    }

    let id = UUID()
    let origin: String
    let capability: Capability
}

struct ScannerRequest: Identifiable {
    let id = UUID()
    let requestId: String
    let origin: String
    let documentId: String
    let generation: UUID
}

@MainActor
final class DuoBridge: ObservableObject {
    @Published private(set) var panel: DuoPanel?
    @Published private(set) var origin: String?
    @Published var permissionRequest: DuoPermissionRequest?
    @Published var scannerRequest: ScannerRequest?
    @Published var errorMessage: String?
    var isActive = true
    var canPresentNativeUI: (() -> Bool)?
    @Published var browserControlsVisible = false

    private weak var webView: WKWebView?
    private let library: BrowserLibrary
    private let isPrivate: Bool
    private var privatePermissions: [String: SitePermissions] = [:]
    private var limiter = DuoRateLimiter()
    private var generation = UUID()
    private var documentId: String?
    private var permissionCompletion: ((Bool) -> Void)?
    private var gesture: (token: String, expires: TimeInterval)?
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "DuoBridge")

    init(library: BrowserLibrary, isPrivate: Bool) {
        self.library = library
        self.isPrivate = isPrivate
    }

    func install(on webView: WKWebView) throws {
        guard let source = Bundle.main.url(forResource: "duo", withExtension: "js") else {
            throw DuoValidationError("The DuoKit JavaScript SDK is missing from this build.")
        }
        let script = try String(contentsOf: source, encoding: .utf8)
        self.webView = webView
        let controller = webView.configuration.userContentController
        controller.addScriptMessageHandler(DuoMessageProxy(bridge: self), contentWorld: .page, name: "duo")
        controller.addUserScript(WKUserScript(
            source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page
        ))
    }

    func receive(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
        guard limiter.accept() else {
            reject("DuoKit rate limit exceeded. Wait before sending more requests.", reply: reply)
            return
        }
        guard let webView, let origin = DuoOrigin.validated(message: message, webView: webView) else {
            reject("DuoKit requires the active main-frame HTTPS origin or the bundled demo.", reply: reply)
            return
        }
        let request: DuoMessage
        do {
            guard JSONSerialization.isValidJSONObject(message.body) else {
                throw DuoValidationError("Message is not a JSON object.")
            }
            request = try DuoMessageValidator.decode(JSONSerialization.data(withJSONObject: message.body))
        } catch {
            reject(error.localizedDescription, reply: reply)
            return
        }
        guard documentId == nil || documentId == request.documentId else {
            reject("The document is no longer authorized.", reply: reply)
            return
        }
        documentId = request.documentId
        self.origin = origin
        let currentGeneration = generation

        switch request.method {
        case "device.capabilities":
            reply([
                "version": "1.0", "controls": true, "scanner": ScannerView.isSupported,
                "requiresUserGesture": true, "maximumControls": DuoMessageValidator.maximumControls
            ], nil)
        case "controls.clear":
            panel = nil
            gesture = nil
            reply(["ok": true], nil)
        case "controls.set", "controls.update":
            guard let configuration = request.configuration else {
                reject("Missing configuration.", reply: reply)
                return
            }
            if request.method == "controls.update", panel?.id != configuration.id {
                reject("Update must replace the active panel with the same identifier.", reply: reply)
                return
            }
            authorize(.controls, origin: origin) { [weak self] allowed in
                guard let self, self.contextMatches(currentGeneration, origin, request.documentId) else {
                    reply(nil, "The requesting document is no longer active.")
                    return
                }
                guard allowed else {
                    self.reject("Duo Controls permission denied.", reply: reply)
                    return
                }
                self.panel = configuration
                self.browserControlsVisible = false
                reply(["ok": true], nil)
            }
        case "scanner.request":
            guard let requestId = request.requestId, let token = request.gestureToken,
                  let gesture, gesture.token == token,
                  gesture.expires >= ProcessInfo.processInfo.systemUptime,
                  panel != nil, isActive, scannerRequest == nil,
                  canPresentNativeUI?() == true else {
                reject("Scanner requires a fresh native Duo control activation.", reply: reply)
                return
            }
            self.gesture = nil
            authorize(.scanner, origin: origin) { [weak self] allowed in
                guard let self, self.contextMatches(currentGeneration, origin, request.documentId) else {
                    reply(nil, "The requesting document is no longer active.")
                    return
                }
                guard allowed, ScannerView.isSupported else {
                    self.reject(allowed ? "Scanning is unavailable on this device." : "Scanner permission denied.", reply: reply)
                    return
                }
                self.scannerRequest = ScannerRequest(
                    requestId: requestId, origin: origin,
                    documentId: request.documentId, generation: currentGeneration
                )
                reply(["ok": true], nil)
            }
        default:
            reject("Unsupported method.", reply: reply)
        }
    }

    func decidePermission(_ allowed: Bool) {
        guard let request = permissionRequest else { return }
        var permissions = permissions(for: request.origin)
        switch request.capability {
        case .controls: permissions.controls = allowed ? .allow : .deny
        case .scanner: permissions.scanner = allowed ? .allow : .deny
        }
        if isPrivate { privatePermissions[request.origin] = permissions }
        else { library.setPermissions(permissions, for: request.origin) }
        settlePermission(allowed)
    }

    func activate(_ control: DuoControl, value: JSONValue? = nil) {
        guard isActive, let panel, let origin, let documentId,
              panel.controls.contains(where: { $0 == control }),
              control.enabled != false, permissions(for: origin).controls != .deny else { return }
        var payload = control.payload ?? [:]
        if let value {
            payload["value"] = value
            if let index = self.panel?.controls.firstIndex(where: { $0.id == control.id }) {
                self.panel?.controls[index].value = value
            }
        }
        let token = UUID().uuidString
        gesture = (token, ProcessInfo.processInfo.systemUptime + 10)
        deliver(DuoEvent(
            type: "duo.controlActivated", panelId: panel.id, controlId: control.id,
            timestamp: Self.timestamp, payload: payload, gestureToken: token,
            requestId: nil, value: nil, format: nil, error: nil
        ), documentId: documentId)
    }

    func completeScanner(_ result: ScannerOutcome, request: ScannerRequest) {
        guard scannerRequest?.id == request.id else { return }
        scannerRequest = nil
        guard contextMatches(request.generation, request.origin, request.documentId),
              permissions(for: request.origin).scanner != .deny else { return }
        let type: String
        let value: String?
        let format: String?
        let error: String?
        switch result {
        case .scanned(let scannedValue, let scannedFormat):
            type = "duo.scannerResult"; value = scannedValue; format = scannedFormat; error = nil
        case .cancelled:
            type = "duo.scannerCancelled"; value = nil; format = nil; error = nil
        case .failure(let message):
            type = "duo.scannerError"; value = nil; format = nil; error = message
        }
        deliver(DuoEvent(
            type: type, panelId: panel?.id, controlId: nil, timestamp: Self.timestamp,
            payload: [:], gestureToken: nil, requestId: request.requestId,
            value: value, format: format, error: error
        ), documentId: request.documentId)
    }

    func navigationStarted() {
        generation = UUID()
        documentId = nil
        origin = nil
        panel = nil
        gesture = nil
        scannerRequest = nil
        browserControlsVisible = false
        settlePermission(false)
        // Do not reset the limiter on navigation; redirect loops must not evade it.
    }

    func deactivate() {
        isActive = false
        if let scannerRequest { completeScanner(.cancelled, request: scannerRequest) }
        settlePermission(false)
        gesture = nil
    }

    func revoke(origin: String) {
        privatePermissions[origin] = SitePermissions(controls: .deny, scanner: .deny)
        guard self.origin == origin else { return }
        if let scannerRequest { completeScanner(.cancelled, request: scannerRequest) }
        panel = nil
        gesture = nil
        settlePermission(false)
    }

    func tearDown() {
        navigationStarted()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "duo", contentWorld: .page)
        webView?.configuration.userContentController.removeAllUserScripts()
        webView = nil
    }

    private func permissions(for origin: String) -> SitePermissions {
        let saved = isPrivate ? privatePermissions[origin] : library.snapshot.permissions[origin]
        return saved ?? SitePermissions(
            controls: library.settings.defaultDuoPermission,
            scanner: library.settings.defaultScannerPermission
        )
    }

    private func authorize(
        _ capability: DuoPermissionRequest.Capability,
        origin: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard isActive, permissionCompletion == nil else { completion(false); return }
        let permissions = permissions(for: origin)
        let decision = capability == .controls ? permissions.controls : permissions.scanner
        switch decision {
        case .allow: completion(true)
        case .deny: completion(false)
        case .ask:
            guard canPresentNativeUI?() == true else { completion(false); return }
            permissionCompletion = completion
            permissionRequest = DuoPermissionRequest(origin: origin, capability: capability)
        }
    }

    private func settlePermission(_ allowed: Bool) {
        let completion = permissionCompletion
        permissionCompletion = nil
        permissionRequest = nil
        completion?(allowed)
    }

    private func contextMatches(_ generation: UUID, _ origin: String, _ documentId: String) -> Bool {
        isActive && self.generation == generation && self.origin == origin
            && self.documentId == documentId && DuoOrigin.canonical(webView?.url) == origin
    }

    private func deliver(_ event: DuoEvent, documentId: String) {
        struct Envelope: Encodable {
            let documentId: String
            let event: DuoEvent
        }
        do {
            let data = try JSONEncoder().encode(Envelope(documentId: documentId, event: event))
            guard let json = String(data: data, encoding: .utf8) else {
                throw DuoValidationError("The event could not be encoded.")
            }
            // JSON encoding, not string interpolation of labels, protects the JS boundary.
            webView?.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('duo.native', {detail: \(json)}));"
            ) { [weak self] _, error in
                if error != nil {
                    Task { @MainActor [weak self] in
                        self?.logger.error("Duo event delivery failed.")
                        self?.errorMessage = "A Duo event could not reach the page. Reload the website to reconnect."
                    }
                }
            }
        } catch {
            logger.error("Duo event encoding failed.")
            errorMessage = "A Duo event could not be prepared."
        }
    }

    private func reject(_ message: String, reply: (Any?, String?) -> Void) {
        logger.notice("A DuoKit request was rejected.")
        reply(nil, message)
    }

    private static var timestamp: String { ISO8601DateFormatter().string(from: .now) }
}

@MainActor
private final class DuoMessageProxy: NSObject, WKScriptMessageHandlerWithReply {
    weak var bridge: DuoBridge?
    init(bridge: DuoBridge) { self.bridge = bridge }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let bridge else { replyHandler(nil, "This tab is closed."); return }
        bridge.receive(message, reply: replyHandler)
    }
}
