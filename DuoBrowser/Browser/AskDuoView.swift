import SwiftUI

struct AskDuoView: View {
    @ObservedObject var model: BrowserViewModel
    @StateObject private var assistant = AskDuoModel()
    @State private var selectedLink: AskDuoLink?
    @State private var confirmsNavigation = false
    @FocusState private var questionFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    let navigate: (AskDuoNavigation) -> Void

    var body: some View {
        List {
            Section("On-device Apple Intelligence") {
                Text(assistant.availabilityMessage ?? "Apple Intelligence is ready on this device.")
                    .accessibilityIdentifier("askduo.model.status")
                    .accessibilityValue(assistant.availabilityMessage == nil ? "available" : "unavailable")
                Button("Check Apple Intelligence Availability") { assistant.refreshAvailability() }
                Text("Nothing is sent to a cloud model. Private tabs are excluded. Questions and excerpts stay in memory and are cleared when you close this sheet or leave the app.")
                    .font(.footnote)
            }
            if let reason = AskDuoPageReader.blockedReason(for: model) {
                Section { Text(reason).accessibilityIdentifier("askduo.page.blocked") }
            } else {
                Section("1. Choose what Apple Intelligence can read") {
                    Text("Read a bounded visible-text excerpt and up to 12 HTTPS links. Forms, editable fields, hidden content and frames are excluded. Other visible text can still contain personal information: review the preview first.")
                        .font(.footnote)
                    Button(assistant.context == nil ? "Read This Page" : "Read Page Again") {
                        assistant.readPage(model)
                    }
                    .disabled(assistant.isBusy)
                    .accessibilityIdentifier("askduo.capture")
                }
            }
            if let context = assistant.context {
                Section("Reviewed page excerpt") {
                    Text(context.title).font(.headline)
                    Text(context.url.host ?? "DuoKit Demo").font(.caption)
                    Text(verbatim: context.text)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("askduo.context")
                    Text(context.truncated ? "This is a truncated excerpt, not the entire page." : "This is a filtered excerpt, not a complete page copy.")
                        .font(.caption)
                }
                Section("2. Ask about this excerpt") {
                    TextField("What would you like to know?", text: $assistant.question, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($questionFocused)
                        .disabled(assistant.isBusy)
                        .accessibilityIdentifier("askduo.question")
                    Text("\(assistant.question.count)/400 characters").font(.caption)
                    Toggle("Allow a link suggestion", isOn: $assistant.allowsNavigation)
                        .disabled(assistant.isBusy)
                    Button("Ask Apple Intelligence") {
                        questionFocused = false
                        assistant.ask(model)
                    }
                        .disabled(assistant.isBusy || assistant.availabilityMessage != nil || assistant.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.question.count > 400)
                        .accessibilityIdentifier("askduo.ask")
                        .accessibilityValue(assistant.availabilityMessage == nil ? "available" : "unavailable")
                    Text(assistant.isBusy ? "Working locally…" : (assistant.answer == nil ? "No answer yet." : "Answer ready below."))
                        .font(.caption)
                        .accessibilityIdentifier("askduo.request.status")
                        .accessibilityValue(assistant.isBusy ? "busy" : (assistant.answer == nil ? "idle" : "answered"))
                }
                if let answer = assistant.answer {
                    Section("Apple Intelligence answer") {
                        Text(verbatim: answer.text)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("askduo.answer")
                        Text("AI can be wrong. Check the original page. No page action has been performed.")
                            .font(.caption)
                        if let link = answer.link { reviewButton(link, proposed: true) }
                    }
                }
                if !context.links.isEmpty {
                    Section("Links from this page") {
                        Text("These links come from the page, not from AI. Opening one always requires your confirmation.")
                            .font(.caption)
                        ForEach(context.links) { reviewButton($0, proposed: false) }
                    }
                }
            }
            if assistant.isBusy {
                Section {
                    ProgressView("Working locally…")
                    Button("Cancel Request", role: .cancel) { assistant.stop() }
                }
            }
            if let message = assistant.errorMessage {
                Section("Ask Duo could not complete the request") {
                    Text(message).accessibilityIdentifier("askduo.error")
                }
            }
            if let notice = assistant.notice { Section { Text(notice).font(.footnote) } }
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("askduo.content")
        .navigationTitle("Ask Duo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done Typing") { questionFocused = false }
                    .accessibilityIdentifier("askduo.keyboard.done")
            }
        }
        .alert("Open this link?", isPresented: $confirmsNavigation) {
            if let selectedLink {
                Button("Open in This Tab") { assistant.open(selectedLink, model: model, confirmed: navigate) }
                    .accessibilityIdentifier("askduo.confirm.open")
                Button("Cancel", role: .cancel) { self.selectedLink = nil }
            }
        } message: {
            if let selectedLink {
                Text("Opening a link can have side effects. Destination:\n\(selectedLink.url.absoluteString)")
            }
        }
        .onAppear { assistant.refreshAvailability() }
        .onDisappear { assistant.clear() }
        .onChange(of: model.navigationID) { _, _ in clearForPageChange() }
        .onChange(of: model.currentURL) { _, _ in clearForPageChange() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                questionFocused = false
                selectedLink = nil
                confirmsNavigation = false
                assistant.clear(notice: "Page context was cleared when the app became inactive.")
            } else { assistant.refreshAvailability() }
        }
    }

    private func reviewButton(_ link: AskDuoLink, proposed: Bool) -> some View {
        Button {
            selectedLink = link
            confirmsNavigation = true
        } label: {
            VStack(alignment: .leading) {
                Text(proposed ? "Review suggested link: \(link.label)" : link.label)
                Text(link.url.host ?? "").font(.caption)
            }
        }
        .disabled(assistant.isBusy)
        .accessibilityIdentifier(proposed ? "askduo.suggested.link" : "askduo.link.\(link.id)")
    }

    private func clearForPageChange() {
        if let context = assistant.context, context.isCurrent(for: model) { return }
        if assistant.context != nil || assistant.isBusy {
            questionFocused = false
            selectedLink = nil
            confirmsNavigation = false
            assistant.clear(notice: "The page changed. Read it again before asking or opening a link.")
        }
    }
}
