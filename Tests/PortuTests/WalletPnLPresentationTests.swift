import Foundation
@testable import Portu
import PortuCore
import Testing

struct WalletPnLPresentationTests {
    @Test func `estimate disclosure explicitly says it is not tax advice`() {
        #expect(WalletPnLPresentation.estimateDisclosure.localizedCaseInsensitiveContains(
            "not tax advice"))
    }

    @Test func `estimate disclosure identifies unavailable breakdown assets`() {
        #expect(WalletPnLPresentation.estimateDisclosure.localizedCaseInsensitiveContains(
            "unavailable assets"))
    }

    @MainActor
    @Test func `partial wallet scope disclosure names active wallet`() {
        let scope = PortfolioAnalyticsScope(
            accountID: UUID(),
            dataSource: .zerion,
            addresses: [.init(
                family: .evm,
                value: "0x1111111111111111111111111111111111111111")])
        let context = PortfolioAnalyticsRequestContext(
            scope: scope,
            chartRange: .oneMonth,
            currency: .usd,
            implementations: [],
            asOf: Date(timeIntervalSince1970: 1_704_153_600),
            isFullAccountScope: false)
        let disclosure = WalletPnLChartMode.partialScopeDisclosure(
            context: context,
            scopeOptions: [.init(label: "0x111…11111", scope: scope)])

        #expect(disclosure?.contains("0x111…11111") == true)
        #expect(disclosure?.localizedCaseInsensitiveContains("excluded") == true)
    }

    @Test func `presentation includes external and NFT flow metrics`() {
        let pnl = makePnL()

        let rows = WalletPnLPresentation.flowRows(for: pnl)

        #expect(rows.map(\.title) == [
            "Received externally",
            "Sent externally",
            "Sent for NFTs",
            "Received for NFTs"
        ])
        #expect(rows.map(\.value) == [100, 80, 30, 20])
    }

    @Test func `asset rows expose cost gain fee and completeness fields`() throws {
        let row = try #require(WalletPnLPresentation.assetRows(for: makePnL()).first)

        #expect(row.implementationID == "ethereum:")
        #expect(row.averageBuyPrice == 10)
        #expect(row.averageSellPrice == 12)
        #expect(row.realizedGain == 3)
        #expect(row.unrealizedGain == -1)
        #expect(row.totalInvested == 50)
        #expect(row.totalFee == 2)
        #expect(row.completenessLabel == "Mapped asset")
    }

    @Test(arguments: [
        (Decimal(1), WalletPnLDirection.gain),
        (Decimal(-1), .loss),
        (Decimal(0), .unchanged)
    ])
    func `gain direction has non color meaning`(
        value: Decimal,
        expected: WalletPnLDirection) {
        #expect(WalletPnLDirection(value: value) == expected)
        #expect(expected.accessibilityLabel.isEmpty == false)
        #expect(expected.systemImage.isEmpty == false)
    }

    private func makePnL() -> ProviderPnLDTO {
        ProviderPnLDTO(
            range: .oneMonth,
            currency: .usd,
            totalGain: 2,
            receivedExternal: 100,
            sentExternal: 80,
            sentForNFTs: 30,
            receivedForNFTs: 20,
            assets: [
                .init(
                    implementationID: "ethereum:",
                    identity: OnchainTokenIdentity(
                        chain: .ethereum,
                        contractAddress: OnchainTokenIdentity.nativeAssetSentinel),
                    averageBuyPrice: 10,
                    averageSellPrice: 12,
                    totalGain: 2,
                    realizedGain: 3,
                    unrealizedGain: -1,
                    totalFee: 2,
                    totalInvested: 50)
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_704_153_600))
    }
}
