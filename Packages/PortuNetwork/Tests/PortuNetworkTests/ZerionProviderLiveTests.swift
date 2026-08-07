import Foundation
import PortuCore
@testable import PortuNetwork
import Testing

@Suite(.serialized)
struct ZerionProviderLiveTests {
    @Test func `live smoke uses one combined position request when explicitly enabled`() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["PORTU_ZERION_LIVE_TESTS"] == "1",
            let apiKey = environment["ZERION_API_KEY"],
            !apiKey.isEmpty
        else { return }

        let address = environment["ZERION_SMOKE_ADDRESS"]
            ?? "0x00000000219ab540356cBB839CBe05303d7705Fa"
        let context = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [(address, .ethereum)],
            exchangeType: nil)
        let provider = ZerionProvider(client: ZerionAPIClient(apiKey: { apiKey }))

        let positions = try await provider.fetchPositions(context: context)

        #expect(!positions.isEmpty)
    }

    @Test func `live analytics smoke checks wallet chart and PnL when explicitly enabled`() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["PORTU_ZERION_LIVE_TESTS"] == "1",
            let apiKey = environment["ZERION_API_KEY"],
            !apiKey.isEmpty
        else { return }

        let address = environment["ZERION_SMOKE_ADDRESS"]
            ?? "0x00000000219ab540356cBB839CBe05303d7705Fa"
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: address)],
            chainIDs: ["ethereum"])
        let provider = ZerionProvider(client: ZerionAPIClient(apiKey: { apiKey }))
        let syncContext = SyncContext(
            accountId: scope.accountID,
            kind: .wallet,
            addresses: [(address, .ethereum)],
            exchangeType: nil)
        let positions = try await provider.fetchPositions(context: syncContext)
        let implementations = positions
            .flatMap(\.tokens)
            .compactMap {
                OnchainTokenIdentity(
                    chain: $0.chain,
                    contractAddress: $0.contractAddress)
            }

        let history = try await provider.fetchPortfolioValueHistory(
            scope: scope,
            period: .month)
        let pnl = try await provider.fetchPnL(
            scope: scope,
            range: .oneMonth,
            currency: .usd,
            implementations: implementations,
            asOf: .now)
        let summary = try await provider.fetchPortfolioSummary(scope: scope)
        let localTotal = positions
            .flatMap(\.tokens)
            .reduce(Decimal.zero) { partial, token in
                if token.role.isPositive {
                    partial + token.usdValue
                } else if token.role.isBorrow {
                    partial - token.usdValue
                } else {
                    partial
                }
            }
        let providerTotal = scope.chainIDs
            .compactMap { summary.positionsByChain[$0] }
            .reduce(Decimal.zero, +)
        let reconciliation = ZerionPortfolioReconciliation.compare(
            providerTotal: providerTotal,
            localTotal: localTotal,
            absoluteTolerance: 1,
            relativeTolerance: 0.02)

        #expect(history.isEmpty == false)
        #expect(pnl.currency == .usd)
        #expect(reconciliation.isWithinTolerance)
    }

    @Test func `live wallet set analytics runs only with both smoke addresses`() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["PORTU_ZERION_LIVE_TESTS"] == "1",
            let apiKey = environment["ZERION_API_KEY"],
            !apiKey.isEmpty,
            let evmAddress = environment["ZERION_SMOKE_ADDRESS"],
            let solanaAddress = environment["ZERION_SOLANA_SMOKE_ADDRESS"]
        else { return }

        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [
                .init(family: .evm, value: evmAddress),
                .init(family: .solana, value: solanaAddress)
            ])
        let provider = ZerionProvider(client: ZerionAPIClient(apiKey: { apiKey }))

        _ = try await provider.fetchPortfolioValueHistory(scope: scope, period: .week)
        _ = try await provider.fetchPnL(
            scope: scope,
            range: .oneWeek,
            currency: .usd,
            implementations: [],
            asOf: .now)
    }

    @Test func `live Solana analytics and direct fiat denominations are meaningful`() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["PORTU_ZERION_LIVE_TESTS"] == "1",
            let apiKey = environment["ZERION_API_KEY"],
            !apiKey.isEmpty,
            let evmAddress = environment["ZERION_SMOKE_ADDRESS"],
            let solanaAddress = environment["ZERION_SOLANA_SMOKE_ADDRESS"]
        else { return }

        let provider = ZerionProvider(client: ZerionAPIClient(apiKey: { apiKey }))
        let solanaScope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .solana, value: solanaAddress)],
            chainIDs: ["solana"])
        let evmScope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(family: .evm, value: evmAddress)],
            chainIDs: ["ethereum"])

        let solanaHistory = try await provider.fetchPortfolioValueHistory(
            scope: solanaScope,
            period: .week)
        let solanaPnL = try await provider.fetchPnL(
            scope: solanaScope,
            range: .oneWeek,
            currency: .chf,
            implementations: [],
            asOf: .now)
        let evmPnL = try await provider.fetchPnL(
            scope: evmScope,
            range: .oneWeek,
            currency: .eur,
            implementations: [],
            asOf: .now)

        #expect(solanaHistory.isEmpty == false)
        #expect(solanaHistory.allSatisfy { $0.coverage == .providerReported })
        #expect(solanaPnL.currency == .chf)
        #expect(evmPnL.currency == .eur)
    }
}
