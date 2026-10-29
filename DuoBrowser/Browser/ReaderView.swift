import SwiftUI

private extension ReaderTheme {
    var backgroundColor: Color {
        switch self {
        case .paper: Color(uiColor: .systemBackground)
        case .sepia: Color(red: 0.97, green: 0.93, blue: 0.84)
        case .night: Color(red: 0.065, green: 0.075, blue: 0.10)
        }
    }
    var ink: Color {
        switch self {
        case .paper: Color(uiColor: .label)
        case .sepia: Color(red: 0.24, green: 0.19, blue: 0.13)
        case .night: Color(red: 0.90, green: 0.92, blue: 0.96)
        }
    }
}

struct ReaderView: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var library: BrowserLibrary
    @StateObject private var reader = ReaderModel()
    @State private var confirmsPrivateExport = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var baseSize: CGFloat = 19

    private var preferences: ReaderPreferences { library.settings.reader }
    private var fontSize: CGFloat { baseSize * CGFloat(preferences.fontSize) / 19 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if reader.isLoading {
                    ProgressView("Preparing Reading View").frame(maxWidth: .infinity, minHeight: 180)
                }
                if let document = reader.document {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.isPrivate ? "Private Reading" : document.attribution,
                              systemImage: model.isPrivate ? "hand.raised" : "doc.richtext")
                            .font(.subheadline.weight(.medium))
                        Text(document.title)
                            .font(.system(.largeTitle, design: .serif).bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("reader.title")
                        Text("\(document.wordCount) words · \(document.minutesToRead) min read")
                            .font(.caption)
                            .opacity(0.7)
                        if document.truncated {
                            Label("This is a shortened reading snapshot.", systemImage: "info.circle")
                                .font(.caption)
                        }
                    }
                    controls
                    Divider().overlay(preferences.theme.ink.opacity(0.15))
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(document.blocks) { block in
                            blockView(block)
                        }
                    }
                    Text("Reading View is a local text snapshot. Interactive controls, forms, images and embedded frames are not copied. The original page remains unchanged.")
                        .font(.caption)
                        .opacity(0.7)
                }
                if let message = reader.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("reader.error")
                    Button("Try Reading Again") { Task { await reader.load(model) } }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("reader.content")
        .foregroundStyle(preferences.theme.ink)
        .background(preferences.theme.backgroundColor.ignoresSafeArea(.container))
        .navigationTitle("Reading View")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(preferences.theme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await reader.load(model) }
        .onDisappear { reader.close(preserveExport: reader.export != nil) }
        .onChange(of: model.navigationID) { _, _ in
            if reader.document != nil {
                reader.close(preserveExport: reader.export != nil)
                reader.errorMessage = "The original page changed. Open Reading View again."
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { reader.stopSpeech() }
        }
        .sheet(item: $reader.export, onDismiss: { _ = reader.removeExport() }) { item in
            ShareSheet(url: item.url, completion: { _ = reader.removeExport() })
        }
        .alert("Share this private reading snapshot?", isPresented: $confirmsPrivateExport) {
            Button("Create Reading PDF") { reader.sharePDF() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sharing creates a temporary file. Other apps can retain their own copies after you share it.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Reading Theme", selection: Binding(
                get: { preferences.theme },
                set: { value in updatePreferences { $0.theme = value } }
            )) {
                ForEach(ReaderTheme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reader.theme")
            Stepper("Text size: \(preferences.fontSize)", value: Binding(
                get: { preferences.fontSize },
                set: { value in updatePreferences { $0.fontSize = value } }
            ), in: 15...28)
            .accessibilityIdentifier("reader.font")
            HStack(spacing: 16) {
                Button {
                    reader.toggleSpeech()
                } label: {
                    Label(
                        reader.speechState == .speaking ? "Pause" : (reader.speechState == .paused ? "Resume" : "Read Aloud"),
                        systemImage: reader.speechState == .speaking ? "pause.fill" : "speaker.wave.2"
                    )
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("reader.speak")
                if reader.speechState != .stopped {
                    Button("Stop", systemImage: "stop.fill", action: reader.stopSpeech)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("reader.speech.stop")
                }
            }
            Button {
                if model.isPrivate { confirmsPrivateExport = true } else { reader.sharePDF() }
            } label: {
                Label("Share Reading PDF", systemImage: "square.and.arrow.up")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("reader.export")
        }
        .tint(preferences.theme == .night ? .cyan : .blue)
        .buttonStyle(.borderless)
    }

    private func blockView(_ block: ReaderBlock) -> some View {
        Text(verbatim: block.kind == .list ? "• " + block.text : block.text)
            .font(block.kind == .heading
                ? .system(size: fontSize * (block.level == 1 ? 1.5 : 1.2), weight: .semibold, design: .serif)
                : .system(size: fontSize, design: block.kind == .code ? .monospaced : .serif))
            .lineSpacing(fontSize * 0.3)
            .padding(.leading, block.kind == .quote ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func updatePreferences(_ update: (inout ReaderPreferences) -> Void) {
        var settings = library.settings
        update(&settings.reader)
        library.updateSettings(settings)
    }
}
