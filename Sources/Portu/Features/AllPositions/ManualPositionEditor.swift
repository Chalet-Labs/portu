import SwiftData
import SwiftUI
import PortuCore

struct ManualPositionEditor: View {
    static let assetInputModeTitles = ["Select Existing", "Create New"]

    struct ResolvedAssetInput: Equatable {
        let existingAssetID: Asset.ID?
        let symbol: String
        let name: String
    }

    private enum AssetInputMode: String, CaseIterable, Identifiable {
        case existing
        case new

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .existing:
                ManualPositionEditor.assetInputModeTitles[0]
            case .new:
                ManualPositionEditor.assetInputModeTitles[1]
            }
        }
    }

    enum SubmissionError: LocalizedError {
        case missingManualAccount
        case invalidAmount
        case invalidAsset
        case invalidUSDValue

        var errorDescription: String? {
            switch self {
            case .missingManualAccount:
                "Select a manual account."
            case .invalidAmount:
                "Enter a valid amount greater than zero."
            case .invalidAsset:
                "Enter an asset symbol."
            case .invalidUSDValue:
                "Enter a valid USD value override."
            }
        }
    }

    struct Submission {
        var accountID: Account.ID?
        var existingAssetID: Asset.ID?
        var assetSymbol: String
        var assetName: String
        var amount: Decimal
        var positionType: PositionType
        var protocolName: String?
        var usdValueOverride: Decimal?

        @MainActor
        func save(in modelContext: ModelContext) throws -> Position {
            let assetSymbol = trimmed(assetSymbol)
            let assetName = trimmed(assetName)

            guard let accountID else {
                throw SubmissionError.missingManualAccount
            }

            guard amount > 0 else {
                throw SubmissionError.invalidAmount
            }

            guard assetSymbol.isEmpty == false else {
                throw SubmissionError.invalidAsset
            }

            let account = try fetchManualAccount(id: accountID, in: modelContext)
            let asset = try fetchAsset(
                existingAssetID: existingAssetID,
                symbol: assetSymbol,
                name: assetName.isEmpty ? assetSymbol : assetName,
                in: modelContext
            )
            let tokenRole = tokenRole(for: positionType)
            let normalizedAmount = absoluteValue(of: amount)
            let normalizedUSDValue = absoluteValue(of: usdValueOverride ?? .zero)

            let position = Position(
                positionType: positionType,
                netUSDValue: normalizedUSDValue,
                protocolName: normalizedOptional(protocolName),
                account: account
            )

            let token = PositionToken(
                role: tokenRole,
                amount: normalizedAmount,
                usdValue: normalizedUSDValue,
                asset: asset,
                position: position
            )

            position.tokens = [token]
            account.positions.append(position)
            modelContext.insert(position)

            do {
                try modelContext.save()
                return position
            } catch {
                modelContext.rollback()
                throw error
            }
        }

        @MainActor
        private func fetchManualAccount(
            id accountID: Account.ID,
            in modelContext: ModelContext
        ) throws -> Account {
            let descriptor = FetchDescriptor<Account>()
            let account = try modelContext.fetch(descriptor).first { account in
                account.id == accountID
                    && account.kind == .manual
                    && account.dataSource == .manual
                    && account.isActive
            }

            guard let account else {
                throw SubmissionError.missingManualAccount
            }

            return account
        }

        @MainActor
        private func fetchOrCreateAsset(
            symbol: String,
            name: String,
            in modelContext: ModelContext
        ) throws -> Asset {
            let descriptor = FetchDescriptor<Asset>(
                predicate: #Predicate {
                    $0.symbol == symbol
                }
            )

            if let asset = try modelContext.fetch(descriptor).first {
                return asset
            }

            let asset = Asset(symbol: symbol, name: name)
            modelContext.insert(asset)
            return asset
        }

        @MainActor
        private func fetchAsset(
            existingAssetID: Asset.ID?,
            symbol: String,
            name: String,
            in modelContext: ModelContext
        ) throws -> Asset {
            if let existingAssetID {
                let descriptor = FetchDescriptor<Asset>()
                if let asset = try modelContext.fetch(descriptor).first(where: { $0.id == existingAssetID }) {
                    return asset
                }
            }

            return try fetchOrCreateAsset(
                symbol: symbol,
                name: name,
                in: modelContext
            )
        }

        private func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func normalizedOptional(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        private func absoluteValue(
            of value: Decimal
        ) -> Decimal {
            value < .zero ? -value : value
        }

        private func tokenRole(
            for positionType: PositionType
        ) -> TokenRole {
            switch positionType {
            case .idle, .vesting, .other:
                return .balance
            case .lending:
                return .supply
            case .liquidityPool, .farming:
                return .lpToken
            case .staking:
                return .stake
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name)
    private var accounts: [Account]
    @Query(sort: \Asset.symbol)
    private var assets: [Asset]

    @State private var selectedAccountID: Account.ID?
    @State private var assetInputMode: AssetInputMode = .existing
    @State private var selectedExistingAssetID: Asset.ID?
    @State private var assetSymbol = ""
    @State private var assetName = ""
    @State private var amount = ""
    @State private var positionType: PositionType = .idle
    @State private var protocolName = ""
    @State private var usdValueOverride = ""
    @State private var errorMessage: String?

    private let onComplete: @MainActor () -> Void

    init(onComplete: @escaping @MainActor () -> Void = {}) {
        self.onComplete = onComplete
    }

    private var manualAccounts: [Account] {
        accounts.filter { account in
            account.kind == .manual
                && account.dataSource == .manual
                && account.isActive
        }
    }

    private var availableAssets: [Asset] {
        assets
    }

    var body: some View {
        Form {
            Picker("Account", selection: $selectedAccountID) {
                Text("Select Account").tag(nil as Account.ID?)

                ForEach(manualAccounts, id: \.id) { account in
                    Text(account.name).tag(account.id as Account.ID?)
                }
            }

            if availableAssets.isEmpty == false {
                Picker("Asset Mode", selection: $assetInputMode) {
                    ForEach(AssetInputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            if usesExistingAssetSelection {
                Picker("Saved Asset", selection: $selectedExistingAssetID) {
                    Text("Select Asset").tag(nil as Asset.ID?)

                    ForEach(availableAssets, id: \.id) { asset in
                        Text("\(asset.symbol) · \(asset.name)").tag(asset.id as Asset.ID?)
                    }
                }
            } else {
                TextField("Asset Symbol", text: $assetSymbol)
                TextField("Asset Name", text: $assetName)
            }

            TextField("Amount", text: $amount)
                .textContentType(.none)

            Picker("Position Type", selection: $positionType) {
                ForEach(PositionType.allCases, id: \.self) { positionType in
                    Text(positionType.rawValue.capitalized).tag(positionType)
                }
            }

            TextField("Protocol Name", text: $protocolName)
            TextField("USD Value Override", text: $usdValueOverride)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button("Save Manual Position") {
                save()
            }
            .disabled(
                selectedAccountID == nil
                    || amountDecimal == nil
                    || usdValueOverrideIsInvalid
                    || assetSelectionIsInvalid
            )
        }
        .formStyle(.grouped)
    }

    private var amountDecimal: Decimal? {
        Decimal(string: amount.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var usdValueOverrideIsInvalid: Bool {
        let trimmed = usdValueOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && Decimal(string: trimmed) == nil
    }

    private var usesExistingAssetSelection: Bool {
        availableAssets.isEmpty == false && assetInputMode == .existing
    }

    private var assetSelectionIsInvalid: Bool {
        if usesExistingAssetSelection {
            return selectedExistingAssetID == nil
        }

        return assetSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard let amountDecimal else {
            errorMessage = SubmissionError.invalidAmount.localizedDescription
            return
        }

        let resolvedAssetInput = Self.resolveAssetInput(
            usesExistingAssetSelection: usesExistingAssetSelection,
            selectedExistingAssetID: selectedExistingAssetID,
            typedAssetSymbol: assetSymbol,
            typedAssetName: assetName,
            availableAssets: availableAssets
        )

        let parsedUSDValueOverride: Decimal?
        do {
            parsedUSDValueOverride = try Self.parseUSDValueOverride(usdValueOverride)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let submission = Submission(
            accountID: selectedAccountID,
            existingAssetID: resolvedAssetInput.existingAssetID,
            assetSymbol: resolvedAssetInput.symbol,
            assetName: resolvedAssetInput.name,
            amount: amountDecimal,
            positionType: positionType,
            protocolName: protocolName,
            usdValueOverride: parsedUSDValueOverride
        )

        do {
            _ = try submission.save(in: modelContext)
            errorMessage = nil
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func resolveAssetInput(
        usesExistingAssetSelection: Bool,
        selectedExistingAssetID: Asset.ID?,
        typedAssetSymbol: String,
        typedAssetName: String,
        availableAssets: [Asset]
    ) -> ResolvedAssetInput {
        if usesExistingAssetSelection,
           let selectedExistingAssetID,
           let selectedAsset = availableAssets.first(where: { $0.id == selectedExistingAssetID }) {
            return ResolvedAssetInput(
                existingAssetID: selectedAsset.id,
                symbol: selectedAsset.symbol,
                name: selectedAsset.name
            )
        }

        let symbol = typedAssetSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = typedAssetName.trimmingCharacters(in: .whitespacesAndNewlines)

        return ResolvedAssetInput(
            existingAssetID: nil,
            symbol: symbol,
            name: trimmedName.isEmpty ? symbol : trimmedName
        )
    }

    static func parseUSDValueOverride(
        _ value: String
    ) throws -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        guard let decimal = Decimal(string: trimmed) else {
            throw SubmissionError.invalidUSDValue
        }

        return decimal
    }
}
