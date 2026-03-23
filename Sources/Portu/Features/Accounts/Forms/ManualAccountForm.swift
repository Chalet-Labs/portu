import SwiftData
import SwiftUI
import PortuCore

struct ManualAccountForm: View {
    struct Submission {
        var name: String
        var notes: String

        @MainActor
        func save(in modelContext: ModelContext) throws -> Account {
            let account = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .manual,
                dataSource: .manual,
                notes: normalizedOptional(notes)
            )

            modelContext.insert(account)
            do {
                try modelContext.save()
                return account
            } catch {
                modelContext.rollback()
                throw error
            }
        }

        private func normalizedOptional(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    private let onComplete: @MainActor () -> Void

    init(onComplete: @escaping @MainActor () -> Void = {}) {
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Description", text: $notes, axis: .vertical)
                .lineLimit(4, reservesSpace: true)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button("Save Manual Account") {
                save()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .formStyle(.grouped)
    }

    private func save() {
        do {
            let submission = Submission(name: name, notes: notes)
            _ = try submission.save(in: modelContext)
            errorMessage = nil
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
