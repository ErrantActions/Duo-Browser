import SwiftUI

struct SiteNavigationView: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var navigation: SiteNavigationModel
    let navigate: (SiteNavigationAction) -> Void

    var body: some View {
        List {
            Section {
                Label("Detected on this website", systemImage: "list.bullet")
                    .font(.headline)
                Text(navigation.origin ?? "Open a verified HTTPS page or the DuoKit demo.")
                    .font(.caption).textSelection(.enabled)
                Text("Duo reads main navigation locally. It does not use AI, hide the website's menu, or click scripted buttons. DuoKit controls take priority.")
                    .font(.footnote).foregroundStyle(.secondary)
                if model.isPrivate {
                    Label("Private choices stay in this tab only", systemImage: "hand.raised")
                        .font(.caption)
                }
                if model.bridge.panel != nil {
                    Label("This website supplies DuoKit controls", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                }
                Toggle("Use Detected Navigation for This Site", isOn: Binding(
                    get: { navigation.preferences.enabled },
                    set: { value in navigation.updatePreferences { $0.enabled = value } }
                ))
                .disabled(navigation.origin == nil)
                .accessibilityIdentifier("site.navigation.enabled")
                Button("Refresh Detected Navigation") { navigation.refreshForReview() }
                    .disabled(navigation.origin == nil || navigation.isRefreshing || !navigation.detectionEnabled)
                    .accessibilityIdentifier("site.navigation.refresh")
                Text("Automatic detection must also be enabled in Settings. Up to three links appear in the controls; pinned links come first. Hide affects only Duo's shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if navigation.isRefreshing { Section { ProgressView("Reading navigation...") } }
            if let error = navigation.errorMessage {
                Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("site.navigation.error") }
            }
            if let snapshot = navigation.snapshot {
                if snapshot.links.isEmpty {
                    Section {
                        Text("No clear primary navigation was found. Use the website's own menu; Duo will not guess.")
                            .accessibilityIdentifier("site.navigation.empty")
                    }
                }
                ForEach(Array(snapshot.links.enumerated()), id: \.element.id) { index, link in
                    Section {
                        Button {
                            Task { @MainActor in
                                do { navigate(try await navigation.prepare(link)) }
                                catch { navigation.showValidationError(error) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label { Text(verbatim: link.label) } icon: { Image(systemName: link.icon) }
                                Text(verbatim: link.url.absoluteString)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .disabled(navigation.isOpening || model.bridge.panel != nil || !navigation.preferences.enabled)
                        .accessibilityIdentifier("site.navigation.link.\(index)")
                        Toggle("Show in Duo Controls", isOn: Binding(
                            get: { !navigation.preferences.hidden.contains(link.id) },
                            set: { visible in
                                navigation.updatePreferences {
                                    if visible { $0.hidden.removeAll { $0 == link.id } }
                                    else {
                                        if !$0.hidden.contains(link.id) { $0.hidden.append(link.id) }
                                        $0.pinned.removeAll { $0 == link.id }
                                    }
                                }
                            }
                        ))
                        .accessibilityIdentifier("site.navigation.visible.\(index)")
                        Button(navigation.preferences.pinned.contains(link.id) ? "Unpin Link" : "Pin Link", systemImage: "pin") {
                            navigation.updatePreferences {
                                if $0.pinned.contains(link.id) { $0.pinned.removeAll { $0 == link.id } }
                                else {
                                    $0.hidden.removeAll { $0 == link.id }
                                    $0.pinned.append(link.id)
                                }
                            }
                        }
                        .disabled(!navigation.preferences.pinned.contains(link.id) && navigation.preferences.pinned.count >= 3)
                        .accessibilityIdentifier("site.navigation.pin.\(index)")
                    }
                }
            }
            Section {
                Button("Reset This Site's Choices", role: .destructive) {
                    navigation.updatePreferences { $0 = SiteNavigationPreferences() }
                }
                .disabled(navigation.origin == nil)
            }
        }
        .accessibilityIdentifier("site.navigation.list")
        .navigationTitle("Site Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if navigation.detectionEnabled, model.bridge.panel == nil { navigation.refreshForReview() }
        }
    }
}
