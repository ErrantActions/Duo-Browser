import SwiftUI

struct DuoCapabilityPresentation: ViewModifier {
    @ObservedObject var bridge: DuoBridge
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(
                get: { enabled ? bridge.scannerRequest : nil },
                set: { request in
                    if enabled, request == nil, let pending = bridge.scannerRequest {
                        bridge.completeScanner(.cancelled, request: pending)
                    }
                }
            )) { request in
                ScannerView { bridge.completeScanner($0, request: request) }
                    .interactiveDismissDisabled()
            }
            .confirmationDialog(
                "Website Permission",
                isPresented: Binding(
                    get: { enabled && bridge.permissionRequest != nil },
                    set: { if enabled && !$0 { bridge.decidePermission(false) } }
                ),
                titleVisibility: .visible
            ) {
                Button("Allow for This Site") { bridge.decidePermission(true) }
                Button("Deny for This Site", role: .destructive) { bridge.decidePermission(false) }
            } message: {
                if let request = bridge.permissionRequest {
                    Text("\(request.origin) requests \(request.capability.rawValue). \(request.capability == .scanner ? "Scanning opens the camera only after you activate a native control." : "This site can display native controls in the Duo Panel.") You can revoke access in Duo Site Permissions.")
                }
            }
    }
}
