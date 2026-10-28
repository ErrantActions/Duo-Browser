import SwiftUI

struct PageDialogView: View {
    let dialog: PageDialog
    let complete: (String?) -> Void
    @State private var response: String

    init(dialog: PageDialog, complete: @escaping (String?) -> Void) {
        self.dialog = dialog
        self.complete = complete
        _response = State(initialValue: dialog.defaultText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Message from Website") {
                    Text(dialog.website)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(dialog.message)
                        .textSelection(.enabled)
                    if dialog.kind == .prompt {
                        TextField("Response", text: $response, axis: .vertical)
                            .accessibilityLabel("Response to website")
                    }
                }
                Section {
                    Button("OK") {
                        complete(dialog.kind == .prompt ? response : "confirmed")
                    }
                    .frame(minHeight: 44)
                    if dialog.kind != .alert {
                        Button("Cancel", role: .cancel) { complete(nil) }
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("Website Dialog")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
