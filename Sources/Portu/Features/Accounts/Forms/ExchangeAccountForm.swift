import SwiftData
import SwiftUI
import PortuCore

struct ExchangeAccountForm: View {
    enum SubmissionError: LocalizedError {
        case cleanupFailed(secretPersistenceError: Error, cleanupError: Error)

        var errorDescription: String? {
            switch self {
            case .cleanupFailed(_, let cleanupError):
                "Account cleanup failed after a secret persistence error: \(cleanupError.localizedDescription)"
            }
        }
    }

    struct Submission {
        typealias CleanupAccount = @MainActor (_ account: Account, _ modelContext: ModelContext) throws -> Void

        private static let persistCleanup: CleanupAccount = { account, modelContext in
            modelContext.delete(account)
            try modelContext.save()
        }

        var name: String
        var exchangeType: ExchangeType
        var apiKey: String
        var apiSecret: String
        var passphrase: String = ""
        var group: String = ""
        var notes: String = ""

        @MainActor
        func save(
            in modelContext: ModelContext,
            secretsCoordinator: AccountSecretsCoordinator,
            cleanupAccount: CleanupAccount = Self.persistCleanup
        ) async throws -> Account {
            let account = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .exchange,
                dataSource: .exchange,
                exchangeType: exchangeType,
                group: normalizedOptional(group),
                notes: normalizedOptional(notes)
            )

            modelContext.insert(account)
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }

            do {
                try await secretsCoordinator.saveExchangeSecrets(
                    accountID: account.id,
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                    passphrase: passphrase
                )
                return account
            } catch {
                let secretPersistenceError = error

                do {
                    try cleanupAccount(account, modelContext)
                } catch {
                    throw SubmissionError.cleanupFailed(
                        secretPersistenceError: secretPersistenceError,
                        cleanupError: error
                    )
                }

                throw secretPersistenceError
            }
        }

        private func normalizedOptional(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var exchangeType: ExchangeType = .kraken
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var passphrase = ""
    @State private var group = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let secretsCoordinator: AccountSecretsCoordinator
    private let onComplete: @MainActor () -> Void

    init(
        secretsCoordinator: AccountSecretsCoordinator = AccountSecretsCoordinator(),
        onComplete: @escaping @MainActor () -> Void = {}
    ) {
        self.secretsCoordinator = secretsCoordinator
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)

            Picker("Exchange", selection: $exchangeType) {
                ForEach(ExchangeType.allCases, id: \.self) { exchangeType in
                    Text(exchangeType.rawValue.capitalized).tag(exchangeType)
                }
            }

            TextField("API Key", text: $apiKey)
            SecureField("API Secret", text: $apiSecret)
            SecureField("Passphrase", text: $passphrase)
            TextField("Group", text: $group)
            TextField("Description", text: $notes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button(isSaving ? "Saving..." : "Save Exchange Account") {
                save()
            }
            .disabled(
                isSaving
                    || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .formStyle(.grouped)
    }

    private func save() {
        let submission = Submission(
            name: name,
            exchangeType: exchangeType,
            apiKey: apiKey,
            apiSecret: apiSecret,
            passphrase: passphrase,
            group: group,
            notes: notes
        )

        isSaving = true
        errorMessage = nil

        Task {
            do {
                _ = try await submission.save(
                    in: modelContext,
                    secretsCoordinator: secretsCoordinator
                )
                errorMessage = nil
                isSaving = false
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
