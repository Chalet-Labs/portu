import Foundation
import SwiftData
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Manual Position Editor Tests")
struct ManualPositionEditorTests {
    @Test func manualPositionEditorExposesSelectAndCreateAssetModes() {
        #expect(ManualPositionEditor.assetInputModeTitles == ["Select Existing", "Create New"])
    }

    @Test func manualPositionEditorResolveAssetInputIgnoresStaleSavedAssetWhenCreatingNew() throws {
        let harness = try ManualPositionEditorHarness.make()
        let existingAsset = harness.insertAsset(symbol: "SOL", name: "Solana")

        let selection = ManualPositionEditor.resolveAssetInput(
            usesExistingAssetSelection: false,
            selectedExistingAssetID: existingAsset.id,
            typedAssetSymbol: "ETH",
            typedAssetName: "Ethereum",
            availableAssets: try harness.savedAssets()
        )

        #expect(selection.existingAssetID == nil)
        #expect(selection.symbol == "ETH")
        #expect(selection.name == "Ethereum")
    }

    @Test func manualPositionEditorRejectsInvalidNonEmptyUSDOverride() {
        #expect(throws: ManualPositionEditor.SubmissionError.invalidUSDValue) {
            _ = try ManualPositionEditor.parseUSDValueOverride("abc")
        }
    }

    @Test func manualPositionSubmissionRejectsZeroAmount() throws {
        let harness = try ManualPositionEditorHarness.make()

        do {
            _ = try harness.submit(
                amount: 0,
                symbol: "SOL",
                accountID: try harness.manualAccount(named: "Ledger").id
            )
            Issue.record("Expected validation failure")
        } catch {
            #expect(error is ManualPositionEditor.SubmissionError)
        }

        #expect(try harness.savedAssets().isEmpty)
        #expect(try harness.savedPositions().isEmpty)
    }

    @Test func manualPositionSubmissionCreatesPositionUsingExistingAsset() throws {
        let harness = try ManualPositionEditorHarness.make()
        let existingAsset = harness.insertAsset(symbol: "SOL", name: "Solana")

        let position = try harness.submit(
            amount: 2,
            symbol: "SOL",
            accountID: try harness.manualAccount(named: "Ledger").id,
            protocolName: "Wallet",
            usdValueOverride: 300
        )

        let savedAssets = try harness.savedAssets()
        let savedPositions = try harness.savedPositions()
        let token = try #require(position.tokens.first)

        #expect(savedAssets.count == 1)
        #expect(savedPositions.count == 1)
        #expect(position.account?.name == "Ledger")
        #expect(position.positionType == .idle)
        #expect(position.protocolName == "Wallet")
        #expect(position.netUSDValue == 300)
        #expect(token.role == .balance)
        #expect(token.amount == 2)
        #expect(token.usdValue == 300)
        #expect(token.asset?.id == existingAsset.id)
    }

    @Test func manualPositionSubmissionCreatesAssetWhenMissing() throws {
        let harness = try ManualPositionEditorHarness.make()

        let position = try harness.submit(
            amount: 1.5,
            symbol: "ETH",
            accountID: try harness.manualAccount(named: "Ledger").id
        )

        let asset = try #require(harness.savedAssets().first)
        let token = try #require(position.tokens.first)

        #expect(try harness.savedAssets().count == 1)
        #expect(try harness.savedPositions().count == 1)
        #expect(asset.symbol == "ETH")
        #expect(asset.name == "ETH")
        #expect(position.account?.name == "Ledger")
        #expect(token.asset?.id == asset.id)
    }

    @Test func manualPositionSubmissionMapsPositionTypeToTokenRole() throws {
        let harness = try ManualPositionEditorHarness.make()
        let ledgerAccountID = try harness.manualAccount(named: "Ledger").id

        let stakingPosition = try harness.submit(
            amount: 4,
            symbol: "ETH",
            accountID: ledgerAccountID,
            positionType: .staking
        )
        let lendingPosition = try harness.submit(
            amount: 10,
            symbol: "USDC",
            accountID: ledgerAccountID,
            positionType: .lending
        )

        #expect(try #require(stakingPosition.tokens.first).role == .stake)
        #expect(try #require(lendingPosition.tokens.first).role == .supply)
    }

    @Test func manualPositionSubmissionTargetsManualAccountByID() throws {
        let harness = try ManualPositionEditorHarness.make()
        _ = harness.insertManualAccount(name: "Ledger")
        let duplicateAccounts = try harness.manualAccounts(named: "Ledger")
        let firstLedger = try #require(duplicateAccounts.first)
        let secondLedger = try #require(duplicateAccounts.last)

        let position = try harness.submit(
            amount: 3,
            symbol: "ETH",
            accountID: secondLedger.id
        )

        #expect(position.account?.id == secondLedger.id)
        #expect(position.account?.id != firstLedger.id)
    }
}

@MainActor
private struct ManualPositionEditorHarness {
    let container: ModelContainer

    static func make() throws -> Self {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext

        let ledger = Account(
            name: "Ledger",
            kind: .manual,
            dataSource: .manual
        )
        let backup = Account(
            name: "Backup",
            kind: .manual,
            dataSource: .manual
        )
        let hidden = Account(
            name: "Wallet",
            kind: .wallet,
            dataSource: .zapper
        )

        context.insert(ledger)
        context.insert(backup)
        context.insert(hidden)
        try context.save()

        return Self(container: container)
    }

    func submit(
        amount: Decimal,
        symbol: String,
        accountID: Account.ID,
        positionType: PositionType = .idle,
        protocolName: String? = nil,
        usdValueOverride: Decimal? = nil,
        existingAssetID: Asset.ID? = nil
    ) throws -> Position {
        let submission = ManualPositionEditor.Submission(
            accountID: accountID,
            existingAssetID: existingAssetID,
            assetSymbol: symbol,
            assetName: symbol,
            amount: amount,
            positionType: positionType,
            protocolName: protocolName,
            usdValueOverride: usdValueOverride
        )

        return try submission.save(in: container.mainContext)
    }

    func insertAsset(symbol: String, name: String) -> Asset {
        let asset = Asset(symbol: symbol, name: name)
        container.mainContext.insert(asset)
        try? container.mainContext.save()
        return asset
    }

    func insertManualAccount(name: String) -> Account {
        let account = Account(
            name: name,
            kind: .manual,
            dataSource: .manual
        )
        container.mainContext.insert(account)
        try? container.mainContext.save()
        return account
    }

    func manualAccount(named name: String) throws -> Account {
        let account = try manualAccounts(named: name).first { _ in true }
        return try #require(account)
    }

    func manualAccounts(named name: String) throws -> [Account] {
        try container.mainContext.fetch(FetchDescriptor<Account>())
            .filter {
                $0.name == name
                    && $0.kind == .manual
                    && $0.dataSource == .manual
                    && $0.isActive
            }
    }

    func savedAssets() throws -> [Asset] {
        try container.mainContext.fetch(FetchDescriptor<Asset>())
    }

    func savedPositions() throws -> [Position] {
        try container.mainContext.fetch(FetchDescriptor<Position>())
    }
}
