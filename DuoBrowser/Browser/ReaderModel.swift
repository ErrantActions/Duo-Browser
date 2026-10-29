import AVFoundation
import Combine
import OSLog
import UIKit

struct ReaderExport: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class ReaderModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum SpeechState { case stopped, speaking, paused }
    @Published private(set) var document: ReaderDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var speechState = SpeechState.stopped
    @Published var export: ReaderExport?
    @Published var errorMessage: String?
    private var operationID = UUID()
    private var deadline: Task<Void, Error>?
    private var synthesizer: AVSpeechSynthesizer?
    private var exportFolder: URL?
    private let logger = Logger(subsystem: "com.duobrowser.app", category: "Reading")

    func load(_ model: BrowserViewModel) async {
        close()
        errorMessage = nil
        let id = UUID()
        operationID = id
        isLoading = true
        deadline = Task { @MainActor [weak self] in
            try await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, self.operationID == id else { return }
            self.operationID = UUID()
            self.isLoading = false
            self.errorMessage = "Reading View timed out. Try opening it again after the page finishes loading."
        }
        do {
            let result = try await AskDuoPageReader.readArticle(from: model)
            try Task.checkCancellation()
            guard operationID == id else { return }
            deadline?.cancel()
            deadline = nil
            document = result
            isLoading = false
        } catch {
            guard operationID == id else { return }
            deadline?.cancel()
            deadline = nil
            isLoading = false
            if !(error is CancellationError) {
                logger.error("Reading extraction failed: code \((error as NSError).code)")
                errorMessage = (error as? ReaderError)?.localizedDescription
                    ?? "The readable text could not be extracted from this page."
            }
        }
    }

    func toggleSpeech() {
        guard let document else { errorMessage = "Open a readable page first."; return }
        switch speechState {
        case .speaking:
            guard synthesizer?.pauseSpeaking(at: .word) == true else {
                errorMessage = "Speech could not be paused."
                return
            }
            speechState = .paused
        case .paused:
            guard synthesizer?.continueSpeaking() == true else {
                errorMessage = "Speech could not be resumed. Stop it and start again."
                return
            }
            speechState = .speaking
        case .stopped:
            let voice = AVSpeechSynthesizer()
            voice.delegate = self
            synthesizer = voice
            let utterance = AVSpeechUtterance(string: document.title + "\n\n" + document.spokenText)
            if !document.language.isEmpty {
                utterance.voice = AVSpeechSynthesisVoice(language: document.language)
            }
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speechState = .speaking
            voice.speak(utterance)
        }
    }

    func stopSpeech() {
        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        speechState = .stopped
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(synthesizer)
        Task { @MainActor [weak self] in
            guard let self, let current = self.synthesizer, ObjectIdentifier(current) == identifier else { return }
            self.stopSpeech()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(synthesizer)
        Task { @MainActor [weak self] in
            guard let self, let current = self.synthesizer, ObjectIdentifier(current) == identifier else { return }
            self.stopSpeech()
            self.errorMessage = "Read Aloud was interrupted. You can start it again."
        }
    }

    func sharePDF() {
        guard let document else { errorMessage = "Open a readable page first."; return }
        stopSpeech()
        guard removeExport() else { return }
        do {
            let data = try ReadingPDF.data(for: document)
            let folder = URL.temporaryDirectory
                .appendingPathComponent("DuoReadingExports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            exportFolder = folder
            let url = folder.appendingPathComponent("Reading.pdf")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            export = ReaderExport(url: url)
        } catch {
            logger.error("Reading export failed: code \((error as NSError).code)")
            errorMessage = (error as? ReaderError)?.localizedDescription ?? "The reading PDF could not be saved."
            removeExport()
        }
    }

    @discardableResult
    func removeExport() -> Bool {
        export = nil
        guard let folder = exportFolder else { return true }
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            exportFolder = nil
            return true
        } catch {
            logger.error("Reading export cleanup failed: code \((error as NSError).code)")
            errorMessage = "A temporary reading export could not be removed."
            return false
        }
    }

    func close(preserveExport: Bool = false) {
        operationID = UUID()
        deadline?.cancel()
        deadline = nil
        isLoading = false
        stopSpeech()
        if !preserveExport { removeExport() }
        document = nil
    }
}
