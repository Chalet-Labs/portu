import SwiftData
import SwiftUI
import PortuCore

struct ChainAccountForm: View {
    enum Ecosystem: String, CaseIterable, Identifiable {
        case evm
        case solana
        case bitcoin

        var id: Self { self }

        var title: String {
            switch self {
            case .evm:
                "Ethereum & L2s"
            case .solana:
                "Solana"
            case .bitcoin:
                "Bitcoin"
            }
        }

        var chain: Chain? {
            switch self {
            case .evm:
                nil
            case .solana:
                .solana
            case .bitcoin:
                .bitcoin
            }
        }
    }

    struct Submission {
        var name: String
        var ecosystem: Ecosystem
        var address: String
        var group: String = ""
        var notes: String = ""

        @MainActor
        func save(in modelContext: ModelContext) throws -> Account {
            let account = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .wallet,
                dataSource: .zapper,
                group: normalizedOptional(group),
                notes: normalizedOptional(notes)
            )
            account.addresses = [
                WalletAddress(
                    address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                    chain: ecosystem.chain,
                    account: account
                )
            ]

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
    @State private var ecosystem: Ecosystem = .evm
    @State private var address = ""
    @State private var group = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    private let onComplete: @MainActor () -> Void

    init(onComplete: @escaping @MainActor () -> Void = {}) {
        self.onComplete = onComplete
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)

            Picker("Network Family", selection: $ecosystem) {
                ForEach(Ecosystem.allCases) { ecosystem in
                    Text(ecosystem.title).tag(ecosystem)
                }
            }

            TextField("Address", text: $address)

            TextField("Group", text: $group)
            TextField("Description", text: $notes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button("Save Chain Account") {
                save()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .formStyle(.grouped)
    }

    private func save() {
        do {
            let submission = Submission(
                name: name,
                ecosystem: ecosystem,
                address: address,
                group: group,
                notes: notes
            )
            _ = try submission.save(in: modelContext)
            errorMessage = nil
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
