import Foundation
import SwiftData
import Testing
import PortuCore
import PortuNetwork
@testable import Portu

private enum SyncTestError: Error, Sendable {
    case unavailable
}

private actor StaticPortfolioDataProvider: PortfolioDataProvider {
    let capabilities: ProviderCapabilities
    private let balances: [PositionDTO]
    private let defiPositions: [PositionDTO]

    init(
        balances: [PositionDTO],
        defiPositions: [PositionDTO] = [],
        capabilities: ProviderCapabilities = ProviderCapabilities(
            supportsTokenBalances: true,
            supportsDeFiPositions: false,
            supportsHealthFactors: false
        )
    ) {
        self.balances = balances
        self.defiPositions = defiPositions
        self.capabilities = capabilities
    }

    func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        balances
    }

    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        defiPositions
    }
}

private actor ThrowingPortfolioDataProvider: PortfolioDataProvider {
    let capabilities = ProviderCapabilities(
        supportsTokenBalances: true,
        supportsDeFiPositions: false,
        supportsHealthFactors: false
    )

    func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        throw SyncTestError.unavailable
    }

    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        throw SyncTestError.unavailable
    }
}

@MainActor
private struct SyncEngineHarness {
    let container: ModelContainer
    let appState: AppState
    let engine: SyncEngine
    let failedAccountID: UUID

    static func make(oneSuccessOneFailure: Bool) throws -> Self {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            PortfolioSnapshot.self,
            AccountSnapshot.self,
            AssetSnapshot.self,
            configurations: configuration
        )
        let context = container.mainContext
        let appState = AppState()

        let successAccount = Account(
            name: "Main Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        successAccount.addresses = [
            WalletAddress(address: "0xabc", chain: nil, account: successAccount)
        ]

        let failedAccount = Account(
            name: "Cold Wallet",
            kind: .exchange,
            dataSource: .exchange,
            exchangeType: .kraken
        )

        let failedAsset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")
        let failedPosition = Position(
            positionType: .idle,
            netUSDValue: 1_500,
            chain: nil,
            protocolName: "Legacy Wallet",
            account: failedAccount
        )
        failedPosition.tokens = [
            PositionToken(role: .balance, amount: 0.5, usdValue: 1_500, asset: failedAsset, position: failedPosition)
        ]
        failedAccount.positions = [failedPosition]

        context.insert(failedAsset)
        context.insert(failedPosition)
        context.insert(successAccount)
        context.insert(failedAccount)
        try context.save()

        let successProvider = StaticPortfolioDataProvider(
            balances: [
                PositionDTO(
                    positionType: .idle,
                    chain: .ethereum,
                    protocolId: nil,
                    protocolName: "Wallet",
                    protocolLogoURL: nil,
                    healthFactor: nil,
                    tokens: [
                        TokenDTO(
                            role: .balance,
                            symbol: "ETH",
                            name: "Ethereum",
                            amount: 1,
                            usdValue: 3_200,
                            chain: .ethereum,
                            contractAddress: nil,
                            debankId: nil,
                            coinGeckoId: "ethereum",
                            sourceKey: "zapper:eth",
                            logoURL: nil,
                            category: .major,
                            isVerified: true
                        )
                    ]
                )
            ]
        )

        let failingProvider = ThrowingPortfolioDataProvider()
        let exchangeProvider: any PortfolioDataProvider = oneSuccessOneFailure ? failingProvider : successProvider
        let providerFactory = ProviderFactory(
            zapperProvider: successProvider,
            exchangeProvider: exchangeProvider
        )

        let engine = SyncEngine(
            modelContext: context,
            appState: appState,
            providerFactory: providerFactory,
            snapshotStore: SnapshotStore()
        )

        return Self(
            container: container,
            appState: appState,
            engine: engine,
            failedAccountID: failedAccount.id
        )
    }

    func portfolioSnapshots() throws -> [PortfolioSnapshot] {
        try container.mainContext.fetch(FetchDescriptor<PortfolioSnapshot>())
    }

    func positions(for accountID: UUID) throws -> [Position] {
        try container.mainContext.fetch(FetchDescriptor<Position>())
            .filter { $0.account?.id == accountID }
    }
}

@MainActor
@Suite("Sync Engine Tests")
struct SyncEngineTests {
    @Test func syncEngineMarksPartialFailuresButKeepsSnapshots() async throws {
        let harness = try SyncEngineHarness.make(oneSuccessOneFailure: true)

        try await harness.engine.syncAllAccounts()

        #expect(harness.appState.syncStatus == .completedWithErrors(failedAccounts: ["Cold Wallet"]))

        let snapshots = try harness.portfolioSnapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.isPartial == true)

        let failedPositions = try harness.positions(for: harness.failedAccountID)
        #expect(failedPositions.count == 1)
    }
}
