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
    @State private var newCategory: AssetCategory = .other
    @State private var createNewAsset = false

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
                        Picker("Category", selection: $newCategory) {
                            ForEach(AssetCategory.allCases, id: \.self) { cat in
                                Text(cat.rawValue.capitalized).tag(cat)
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
            asset = Asset(symbol: newSymbol, name: newName, category: newCategory)
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
