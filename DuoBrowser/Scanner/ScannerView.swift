import AVFoundation
import SwiftUI
import Vision
import VisionKit

enum ScannerOutcome {
    case scanned(value: String, format: String)
    case cancelled
    case failure(String)
}

struct ScannerView: View {
    static var isSupported: Bool { DataScannerViewController.isSupported }
    var preferences = ScannerPreferences()
    let complete: (ScannerOutcome) -> Void
    @State private var authorized = false
    @State private var didFinish = false

    var body: some View {
        NavigationStack {
            Group {
                if authorized {
                    CameraScanner(preferences: preferences, complete: finish)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("Preparing Camera")
                }
            }
            .navigationTitle("Scan Barcode or QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish(.cancelled) }
                }
            }
        }
        .task {
            guard Self.isSupported else {
                finish(.failure("Scanning is not supported on this device."))
                return
            }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            if status == .authorized {
                allowed = true
            } else if status == .notDetermined {
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            } else {
                allowed = false
            }
            guard !Task.isCancelled else { return }
            guard allowed, DataScannerViewController.isAvailable else {
                finish(.failure("Camera access is unavailable. Check Camera permissions in iOS Settings."))
                return
            }
            authorized = true
            do {
                try await Task.sleep(for: .seconds(60))
                finish(.failure("The scan timed out. Activate the scan control to try again."))
            } catch is CancellationError {
                return
            } catch {
                finish(.failure("Scanning was interrupted. Try again."))
            }
        }
    }

    private func finish(_ outcome: ScannerOutcome) {
        guard !didFinish else { return }
        didFinish = true
        complete(outcome)
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    let preferences: ScannerPreferences
    let complete: (ScannerOutcome) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(feedback: preferences.feedback, complete: complete) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let barcodes: [VNBarcodeSymbology] = [
            .ean13, .ean8, .code128, .code39, .pdf417, .aztec, .dataMatrix, .upce
        ]
        let symbologies: [VNBarcodeSymbology] = preferences.formats == .qr ? [.qr]
            : (preferences.formats == .barcodes ? barcodes : [.qr] + barcodes)
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            Task { @MainActor in
                context.coordinator.finish(.failure("The camera could not start scanning. Try again."))
            }
        }
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        controller.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let complete: (ScannerOutcome) -> Void
        private let feedback: Bool
        private var finished = false

        init(feedback: Bool, complete: @escaping (ScannerOutcome) -> Void) {
            self.feedback = feedback
            self.complete = complete
        }

        func finish(_ outcome: ScannerOutcome) {
            guard !finished else { return }
            finished = true
            complete(outcome)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    dataScanner.stopScanning()
                    guard !value.isEmpty, value.utf8.count <= 4096 else {
                        finish(.failure("The scanned code is empty or too large. Try a code under 4 KB."))
                        return
                    }
                    if feedback { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    finish(.scanned(value: value, format: barcode.observation.symbology.rawValue))
                    return
                }
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            dataScanner.stopScanning()
            finish(.failure("The camera became unavailable. Try scanning again."))
        }
    }
}
