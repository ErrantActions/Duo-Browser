import SwiftUI

struct AskDuoView: View {
    @ObservedObject var model: BrowserViewModel
    @StateObject private var assistant = AskDuoModel()
    @State private var selectedLink: AskDuoLink?
    @State private var confirmsNavigation = false
    @State private var showsExcerpt = false
    @State private var showsLinks = false
    @State private var sendAfterApproval = false
    @State private var usesPage = false
    @FocusState private var questionFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    var expand: () -> Void = {}
    let navigate: (AskDuoNavigation) -> Void

    private var pageBlockedReason: String? { AskDuoPageReader.blockedReason(for: model) }
    private var blockedReason: String? {
        if model.isPrivate { return "Ask Duo is disabled in Private Browsing. No page will be read." }
        if model.isClosed { return "This tab is closed." }
        return nil
    }

    var body: some View {
        ZStack {
        ScrollViewReader { scroll in
            List {
                if let blockedReason {
                    Section {
                        Text(blockedReason).accessibilityIdentifier("askduo.page.blocked")
                    }
                    if blockedReason == nil, let pageBlockedReason {
                        Section {
                            Text("\(pageBlockedReason) You can still chat without page access.")
                                .font(.footnote).accessibilityIdentifier("askduo.page.blocked")
                        }
                    }
                }
                Section {
                    Label("On-device Apple Intelligence", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Text(assistant.availabilityMessage ?? "Ready for questions, writing help and approved page context.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("askduo.model.status")
                        .accessibilityValue(assistant.availabilityMessage == nil ? "available" : "unavailable")
                    DisclosureGroup("Privacy and availability") {
                        Text("No cloud model or saved chat history. Closing Ask Duo or leaving the app clears the conversation. Only a filtered, approved excerpt is used; this is not web search or automatic clicking.")
                            .font(.footnote)
                        Button("Check Apple Intelligence Availability") { assistant.refreshAvailability() }
                    }
                }
                if blockedReason == nil {
                    Section {
                        if assistant.context == nil {
                            Text("How can I help?")
                                .font(.headline)
                            Text("Chat without sharing a page, or choose a page shortcut and review its excerpt first. This on-device model has no live web search.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if pageBlockedReason == nil {
                                Button("Read This Page") { readPage() }
                                    .disabled(assistant.isBusy)
                                    .accessibilityIdentifier("askduo.capture")
                            }
                        }
                        if pageBlockedReason == nil { HStack(spacing: 8) {
                            quickPrompt("Summarize", question: "Summarize this page in a few sentences.", id: "summary")
                            quickPrompt("Key points", question: "What are the most important points in this page?", id: "points")
                            quickPrompt("Explain", question: "Explain this page in plain language.", id: "explain")
                        }
                        }
                    }
                }
                if let context = assistant.context {
                    Section("Page context") {
                        Label(context.title, systemImage: "doc.text")
                            .font(.subheadline.weight(.medium))
                        Text(context.url.host ?? "DuoKit Demo").font(.caption)
                        if assistant.hasApprovedContext {
                            Label("Using your approved excerpt", systemImage: "checkmark.shield")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Forms, editable fields, hidden content and frames are excluded. Other visible text can contain personal information: review the preview.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button(sendAfterApproval ? "Use This Excerpt and Send" : "Use This Excerpt") {
                                assistant.approvePage(model)
                                if sendAfterApproval, assistant.hasApprovedContext {
                                    sendAfterApproval = false
                                    assistant.ask(model, usingPage: true)
                                }
                            }
                            .disabled(assistant.isBusy)
                            .accessibilityIdentifier("askduo.approve")
                        }
                        Button(showsExcerpt ? "Hide Page Excerpt" : "Show Page Excerpt") { showsExcerpt.toggle() }
                            .accessibilityIdentifier("askduo.preview.toggle")
                        if showsExcerpt {
                            Text(verbatim: context.text)
                                .font(.footnote).textSelection(.enabled)
                                .accessibilityIdentifier("askduo.context")
                            Text(context.truncated ? "A truncated excerpt, not the entire page." : "A filtered excerpt, not a complete page copy.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Read Page Again") { readPage() }
                                .accessibilityIdentifier("askduo.capture")
                            Spacer()
                            Button("Remove Page", role: .destructive) {
                                assistant.clear()
                                usesPage = false
                                sendAfterApproval = false
                                showsLinks = false
                            }
                        }
                        .disabled(assistant.isBusy)
                        Toggle("Suggest page links", isOn: $assistant.allowsNavigation)
                            .disabled(assistant.isBusy)
                        Text("Link suggestions never open anything automatically. Each destination requires confirmation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .id("pageContext")
                }
                ForEach(assistant.conversation.turns) { turn in
                    Section {
                        questionBubble(turn.question)
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Ask Duo", systemImage: "sparkles")
                                .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            Text(verbatim: turn.answer.text)
                                .textSelection(.enabled)
                                .accessibilityIdentifier(turn.id == assistant.conversation.turns.last?.id ? "askduo.answer" : "askduo.answer.\(turn.id.uuidString)")
                            if assistant.allowsNavigation, let link = turn.answer.link {
                                reviewButton(link, proposed: true)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowSeparator(.hidden)
                }
                if let pending = assistant.pendingQuestion {
                    Section {
                        questionBubble(pending)
                        ProgressView("Thinking on device...")
                    }
                } else if assistant.isBusy {
                    Section { ProgressView("Working locally...") }
                }
                if let message = assistant.errorMessage {
                    Section {
                        Label("Couldn't complete the request", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.medium))
                        Text(message).font(.footnote).accessibilityIdentifier("askduo.error")
                    }
                }
                if let notice = assistant.notice {
                    Section { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }
                if let context = assistant.context, !context.links.isEmpty {
                    Section {
                        Button(showsLinks ? "Hide Page Links" : "Show Page Links") { showsLinks.toggle() }
                            .accessibilityIdentifier("askduo.links.toggle")
                        if showsLinks {
                            Text("Links found on the page, not invented by AI. Review the destination before opening.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(context.links) { reviewButton($0, proposed: false) }
                        }
                    }
                }
                Section {
                    Text("AI can be wrong and cannot search the web. Up to six recent exchanges stay in this chat; only the last two shortened exchanges are used for follow-ups. No forms are filled or submitted.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .id("latest")
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("askduo.content")
            .onChange(of: assistant.conversation.turns.last?.id) { _, _ in
                withAnimation { scroll.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: assistant.context?.documentID) { _, documentID in
                if documentID != nil {
                    withAnimation { scroll.scrollTo("pageContext", anchor: .top) }
                }
            }
        }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("askduo.surface")
        .navigationTitle("Ask Duo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Expand Chat", systemImage: "arrow.up.left.and.arrow.down.right", action: expand)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("askduo.expand")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Chat", systemImage: "square.and.pencil") {
                    questionFocused = false
                    sendAfterApproval = false
                    assistant.newChat()
                }
                .accessibilityIdentifier("askduo.newchat")
            }
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
        .onChange(of: usesPage) { _, enabled in
            if !enabled, assistant.context != nil {
                let draft = assistant.question
                assistant.clear(notice: "Page access removed. The page and previous chat are no longer used.")
                assistant.question = draft
                sendAfterApproval = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                questionFocused = false
                selectedLink = nil
                confirmsNavigation = false
                sendAfterApproval = false
                usesPage = false
                assistant.clear(notice: "Page context and chat were cleared when the app became inactive.")
            } else { assistant.refreshAvailability() }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Duo...", text: $assistant.question, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($questionFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .disabled(assistant.isBusy || blockedReason != nil)
                    .accessibilityIdentifier("askduo.question")
                if assistant.isBusy {
                    Button("Stop", systemImage: "stop.circle.fill") { assistant.stop() }
                        .labelStyle(.iconOnly).font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly).font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(blockedReason != nil || assistant.availabilityMessage != nil || assistant.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.question.count > 400)
                        .accessibilityIdentifier("askduo.ask")
                        .accessibilityValue(assistant.availabilityMessage == nil ? "available" : "unavailable")
                }
            }
            Toggle("Use This Page", isOn: $usesPage)
                .font(.caption)
                .disabled(assistant.isBusy || pageBlockedReason != nil)
                .accessibilityIdentifier("askduo.usepage")
            Text(assistant.isBusy ? "Working locally..." : (assistant.answer != nil ? "AI can be wrong. Check important information." : "\(assistant.question.count)/400 · \(usesPage ? "Page excerpt needs approval" : "No page access")"))
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("askduo.request.status")
                .accessibilityValue(assistant.isBusy ? "busy" : (assistant.answer != nil ? "answered" : (assistant.errorMessage != nil ? "failed:\(assistant.failureCode ?? "validation")" : "idle")))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func questionBubble(_ question: String) -> some View {
        HStack {
            Spacer(minLength: 30)
            Text(verbatim: question)
                .padding(12)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("You: \(question)")
        }
    }

    private func quickPrompt(_ title: String, question: String, id: String) -> some View {
        Button(title) {
            usesPage = true
            assistant.question = question
            send()
        }
        .buttonStyle(.bordered).controlSize(.small)
        .frame(minHeight: 44).font(.caption)
        .disabled(assistant.isBusy)
        .accessibilityIdentifier("askduo.quick.\(id)")
    }

    private func readPage() {
        questionFocused = false
        sendAfterApproval = false
        showsExcerpt = false
        showsLinks = false
        usesPage = true
        assistant.readPage(model)
    }

    private func send() {
        questionFocused = false
        guard !assistant.isBusy, blockedReason == nil else { return }
        guard let question = assistant.validatedQuestion() else { return }
        if !usesPage {
            sendAfterApproval = false
            assistant.ask(model, usingPage: false)
        } else if assistant.hasApprovedContext {
            sendAfterApproval = false
            assistant.ask(model)
        } else {
            sendAfterApproval = true
            showsExcerpt = true
            if assistant.context == nil { assistant.readPage(model, question: question) }
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
        if assistant.context != nil || assistant.isBusy || !assistant.conversation.turns.isEmpty {
            questionFocused = false
            selectedLink = nil
            confirmsNavigation = false
            sendAfterApproval = false
            usesPage = false
            assistant.clear(notice: "The page changed. Review it again before continuing the chat or opening a link.")
        }
    }
}
