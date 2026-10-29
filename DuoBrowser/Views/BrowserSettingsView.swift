import SwiftUI

struct BrowserSettingsView: View {
    @ObservedObject var library: BrowserLibrary
    @ObservedObject var manager: BrowserTabManager
    @State private var settings = BrowserSettings()
    @State private var error: String?
    @State private var confirmsClear = false
    @State private var clearing = false
    @State private var loadedSettings = false

    var body: some View {
        Form {
            Section("Browsing") {
                Picker("Search Engine", selection: $settings.searchProvider) {
                    ForEach(SearchProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Start Page (blank for built-in)", text: $settings.startPageAddress)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Restore Regular Tabs", isOn: $settings.restoreTabs)
                Stepper("Maximum Tabs: \(settings.maximumTabs)", value: $settings.maximumTabs, in: 1...100)
                Stepper("History Retention: \(settings.historyRetentionDays) Days", value: $settings.historyRetentionDays, in: 0...365)
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(BrowserAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            Section("Default Website Permissions") {
                Toggle("Block Website Camera and Microphone", isOn: $settings.denyWebsiteMedia)
                Text("Otherwise, WebKit and iOS ask when a website requests access. Location and other website permissions remain subject to iOS prompts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Duo Permissions for New Sites") {
                permissionPicker("Duo Controls", value: $settings.defaultDuoPermission)
                permissionPicker("Scanner", value: $settings.defaultScannerPermission)
                Text("Scanner permission never opens the camera by itself. A fresh native Duo control action and iOS camera permission are still required.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scanner") {
                NavigationLink("Scanner Settings") {
                    ScannerSettingsView(preferences: $settings.scanner) {
                        var saved = library.settings
                        saved.scanner = settings.scanner
                        return library.updateSettings(saved)
                    }
                }
                Text("Choose camera size, barcode types, and text-field input behavior. Save Scanner Settings in the editor to apply only those preferences.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save Settings", action: save)
                Button("Clear Browsing Data", role: .destructive) { confirmsClear = true }
                    .disabled(clearing)
                Text("Clearing closes all tabs, stops active downloads, and removes website cookies/storage, history, and Duo permissions. Bookmarks and completed downloads remain. The built-in start screen opens without contacting your custom start page.")
                    .font(.caption).foregroundStyle(.secondary)
                if clearing { ProgressView("Clearing Website Data") }
            }
            .disabled(manager.isClearingData)
        }
        .navigationTitle("Settings")
        .onAppear {
            if !loadedSettings {
                settings = library.settings
                loadedSettings = true
            }
        }
        .confirmationDialog("Clear browsing data and close all tabs?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear Browsing Data", role: .destructive) {
                clearing = true
                Task { @MainActor in
                    await manager.clearWebsiteData()
                    manager.selectedTab?.deactivate()
                    clearing = false
                }
            }
        }
    }

    private func permissionPicker(_ title: String, value: Binding<SitePermission>) -> some View {
        Picker(title, selection: value) {
            ForEach(SitePermission.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
    }

    private func save() {
        let address = settings.startPageAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            guard let url = URLNormalizer.webURL(from: address) else {
                error = "The start page must be a valid HTTP or HTTPS website."
                return
            }
            settings.startPageAddress = url.absoluteString
        } else {
            settings.startPageAddress = ""
        }
        library.updateSettings(settings)
        error = nil
    }
}

struct ScannerSettingsSection: View {
    @Binding var preferences: ScannerPreferences

    var body: some View {
        Section("Camera") {
            Toggle("Compact Scanner", isOn: $preferences.compact)
                .accessibilityIdentifier("scanner.settings.compact")
            Toggle("Vibrate on Scan", isOn: $preferences.feedback)
                .accessibilityIdentifier("scanner.settings.feedback")
            Picker("Recognize", selection: $preferences.formats) {
                ForEach(ScannerFormats.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("Compact scanning starts in a half-height sheet. Drag it taller if needed. The page cannot be edited behind the scanner.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Scan Into Field") {
            Picker("Insert", selection: $preferences.insertion) {
                ForEach(ScannerInsertion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("After Input", selection: $preferences.suffix) {
                ForEach(ScannerSuffix.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("Enter Events notifies website keyboard handlers; these are not trusted hardware keystrokes. Enter and Submit Form also requests normal form submission if handlers do not cancel Enter. Submission can send data or perform an action. Enable it only on a site you trust.")
                .font(.caption).foregroundStyle(.secondary)
            Text("These input options apply only to Browser Menu → Scan Into Field. DuoKit Scan controls still return a result to the site without typing or submitting.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ScannerSettingsView: View {
    @Binding var preferences: ScannerPreferences
    let save: () -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form { ScannerSettingsSection(preferences: $preferences) }
            .navigationTitle("Scanner Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Scanner Settings") {
                        if save() { dismiss() }
                    }
                    .accessibilityIdentifier("scanner.settings.save")
                }
            }
    }
}

struct SitePermissionsView: View {
    @ObservedObject var library: BrowserLibrary
    @ObservedObject var manager: BrowserTabManager

    var body: some View {
        List {
            if let tab = manager.selectedTab, !tab.isPrivate, let origin = tab.bridge.origin,
               library.snapshot.permissions[origin] == nil {
                Section("Current Site: \(origin)") {
                    Button("Revoke Access", role: .destructive) {
                        library.setPermissions(SitePermissions(controls: .deny, scanner: .deny), for: origin)
                        manager.revokeSite(origin)
                    }
                }
            }
            if let tab = manager.selectedTab, tab.isPrivate, let origin = tab.bridge.origin {
                Section("Private Site") {
                    Text(origin)
                    Button("Revoke Private Site Access", role: .destructive) {
                        tab.bridge.revoke(origin: origin)
                    }
                }
            }
            ForEach(library.snapshot.permissions.keys.sorted(), id: \.self) { origin in
                Section(origin) {
                    Text("Duo Controls: \(library.snapshot.permissions[origin]?.controls.rawValue ?? "ask")")
                    Text("Scanner: \(library.snapshot.permissions[origin]?.scanner.rawValue ?? "ask")")
                    Button("Revoke Access", role: .destructive) {
                        library.setPermissions(SitePermissions(controls: .deny, scanner: .deny), for: origin)
                        manager.revokeSite(origin)
                    }
                    Button("Ask Again Next Time") {
                        library.setPermissions(SitePermissions(), for: origin)
                        manager.revokeSite(origin)
                    }
                }
            }
            Section {
                Text("Permissions are scoped to an exact HTTPS origin, including its port. Private decisions are temporary and are not written to disk. Scanner and camera permission are separate.")
                    .font(.caption)
            }
        }
        .navigationTitle("Duo Site Permissions")
    }
}
