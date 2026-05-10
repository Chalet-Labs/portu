// Sources/Portu/Features/Positions/AddPositionSheet.swift
import PortuCore
import SwiftData
import SwiftUI

struct AddPositionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Account> { $0.isActive == true && $0.dataSource.rawValue == "manual" })
    private var manualAccounts: [Account]
    @Query private var assets: [Asset]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]

    @State private var selectedAccountId: UUID?
    @State private var assetSearch = ""
    @State private var selectedAsset: Asset?
    @State private var amount: Decimal = 0
    @State private var positionType: PositionType = .idle
    @State private var protocolName = ""
    @State private var usdValueOverride: Decimal?

    @State private var saveError: String?

    // New asset fields
    @State private var newSymbol = ""
    @State private var newName = ""
    @State private var newPortfolioCategoryId = PortfolioCategoryDefaults.fallbackCategoryID
    @State private var createNewAsset = false

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var filteredAssets: [Asset] {
        if assetSearch.isEmpty { return Array(assets.prefix(20)) }
        return assets.filter {
            $0.symbol.localizedCaseInsensitiveContains(assetSearch) ||
                $0.name.localizedCaseInsensitiveContains(assetSearch)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Manual Position")
                .font(.headline)
                .padding()

            Form {
                // Account picker
                Picker("Account", selection: $selectedAccountId) {
                    Text("Select account...").tag(nil as UUID?)
                    ForEach(manualAccounts, id: \.id) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }

                // Asset selection
                Section("Asset") {
                    if createNewAsset {
                        TextField("Symbol", text: $newSymbol)
                        TextField("Name", text: $newName)
                        Picker("Category", selection: $newPortfolioCategoryId) {
                            ForEach(categoryResolver.categories) { category in
                                Text(category.name).tag(category.id)
                            }
                        }
                        Button("Use existing asset") { createNewAsset = false }
                    } else {
                        TextField("Search assets...", text: $assetSearch)
                        List(filteredAssets, id: \.id, selection: $selectedAsset) { asset in
                            HStack {
                                Text(asset.symbol).fontWeight(.medium)
                                Text(asset.name).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 120)
                        Button("Create new asset") { createNewAsset = true }
                    }
                }

                // Position details
                Section("Details") {
                    TextField("Amount", value: $amount, format: .number)
                    Picker("Type", selection: $positionType) {
                        ForEach(PositionType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    TextField("Protocol (optional)", text: $protocolName)
                    TextField("USD Value (optional override)", value: $usdValueOverride, format: .currency(code: "USD"))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { savePosition() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAccountId == nil || amount == 0 ||
                        (createNewAsset ? newSymbol.isEmpty || newName.isEmpty : selectedAsset == nil))
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .alert("Save Failed", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func savePosition() {
        guard
            let accountId = selectedAccountId,
            let account = manualAccounts.first(where: { $0.id == accountId }) else { return }

        let asset: Asset
        if createNewAsset {
            let portfolioCategory = categoryResolver.categories.first { $0.id == newPortfolioCategoryId }
                ?? PortfolioCategoryDefaults.fallbackCategory
            do {
                try ManualPositionCategoryRules.upsertGlobalRule(
                    symbol: newSymbol,
                    categoryId: portfolioCategory.id,
                    in: modelContext)
            } catch {
                saveError = error.localizedDescription
                return
            }
            asset = Asset(
                symbol: newSymbol,
                name: newName,
                category: ManualPositionCategoryRules.legacyCategory(for: portfolioCategory))
            modelContext.insert(asset)
        } else if let existing = selectedAsset {
            asset = existing
        } else {
            return
        }

        let livePrice = asset.coinGeckoId.flatMap { appState.prices[$0] }
        let usdValue = usdValueOverride ?? livePrice.map { amount * $0 } ?? 0
        let token = PositionToken(role: .balance, amount: amount, usdValue: usdValue, asset: asset)
        let position = Position(
            positionType: positionType,
            protocolName: protocolName.isEmpty ? nil : protocolName,
            netUSDValue: usdValue,
            tokens: [token],
            account: account,
            syncedAt: .now)
        modelContext.insert(position)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

enum ManualPositionCategoryRules {
    static func legacyCategory(for category: PortfolioCategorySnapshot) -> AssetCategory {
        switch category.id {
        case PortfolioCategoryDefaults.defiCategoryID:
            .defi
        case PortfolioCategoryDefaults.memeCategoryID:
            .meme
        case PortfolioCategoryDefaults.privacyCategoryID:
            .privacy
        case PortfolioCategoryDefaults.fiatCategoryID:
            .fiat
        case PortfolioCategoryDefaults.stablecoinsCategoryID:
            .stablecoin
        default:
            .other
        }
    }

    @MainActor
    static func upsertGlobalRule(
        symbol: String,
        categoryId: UUID,
        in modelContext: ModelContext) throws {
        try upsertGlobalRule(
            symbol: symbol,
            categoryId: categoryId,
            in: modelContext) {
                try modelContext.save()
            }
    }

    @MainActor
    static func upsertGlobalRule(
        symbol: String,
        categoryId: UUID,
        in modelContext: ModelContext,
        save: () throws -> Void) throws {
        try PortfolioCategorySeeder.seedIfNeeded(in: modelContext)

        let normalizedSymbol = PortfolioCategoryDefaults.normalizeSymbol(symbol)
        guard !normalizedSymbol.isEmpty else { return }

        let categoryDescriptor = FetchDescriptor<PortfolioCategory>(
            predicate: #Predicate { $0.id == categoryId })
        guard let category = try modelContext.fetch(categoryDescriptor).first else { return }

        let ruleDescriptor = FetchDescriptor<CategorySymbolRule>(
            predicate: #Predicate { $0.normalizedSymbol == normalizedSymbol })
        let existingRules = try modelContext.fetch(ruleDescriptor)
        let previousRules = existingRules.map(SymbolRuleSnapshot.init)
        let insertedRule: CategorySymbolRule?
        if let firstRule = existingRules.first {
            firstRule.category = category
            for duplicateRule in existingRules.dropFirst() {
                modelContext.delete(duplicateRule)
            }
            insertedRule = nil
        } else {
            let rule = CategorySymbolRule(
                normalizedSymbol: normalizedSymbol,
                category: category)
            modelContext.insert(rule)
            insertedRule = rule
        }

        do {
            try save()
        } catch {
            if let insertedRule {
                modelContext.delete(insertedRule)
            } else {
                if let firstRule = existingRules.first, let firstSnapshot = previousRules.first {
                    firstSnapshot.restore(firstRule)
                }
                for snapshot in previousRules.dropFirst() {
                    modelContext.insert(snapshot.makeRule())
                }
            }
            throw error
        }
    }

    private struct SymbolRuleSnapshot {
        let id: UUID
        let normalizedSymbol: String
        let category: PortfolioCategory?

        init(_ rule: CategorySymbolRule) {
            self.id = rule.id
            self.normalizedSymbol = rule.normalizedSymbol
            self.category = rule.category
        }

        func restore(_ rule: CategorySymbolRule) {
            rule.category = category
        }

        func makeRule() -> CategorySymbolRule {
            CategorySymbolRule(
                id: id,
                normalizedSymbol: normalizedSymbol,
                category: category)
        }
    }
}
