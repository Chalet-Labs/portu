import Foundation
@testable import Portu
import PortuCore
import Testing

/// The Asset Detail page seam (S7, A7, F4, V5, T2, T4, U3, U4) over the shared fixture and
/// variants of it. Every value is worked out by hand in USD from the fixture table.
///
/// The ETH variant is the fixture's three ETH tokens plus a 1 ETH borrow on Arbitrum in the Degen
/// account: wallet 2 (6000), Aave supply 1 (3000) and borrow 0.5 (−1500) on Ethereum, all live 3000
/// with a +25% fraction, and the Arbitrum borrow (−3000). Net 4500, net amount 1.5; per chain
/// Ethereum 2.5 / 7500 and Arbitrum −1 / −3000.
enum AssetDetailSeamFixture {
    typealias Fixture = PortfolioValuationFixture

    static let eth = asset(Fixture.AssetID.eth, "ETH", coinGeckoId: "ethereum")
    static let ethTokens = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.eth }
    static let arbitrumBorrowID = Fixture.uuid(9501)

    /// A 1 ETH borrow on Arbitrum, Aave V3, in the Degen account.
    static func arbitrumBorrow(amount: Decimal = 1) -> ValuationInput {
        ethInput(arbitrumBorrowID, role: .borrow, amount: amount, chain: .arbitrum, position: Fixture.uuid(9601), protocolId: "aave-v3")
    }

    static let ethVariant = ethTokens + [arbitrumBorrow()]

    static func ethInput(
        _ tokenId: UUID,
        role: TokenRole,
        amount: Decimal,
        chain: Chain,
        position: UUID,
        protocolId: String? = nil) -> ValuationInput {
        ValuationInput(
            tokenId: tokenId,
            token: Fixture.token(
                Fixture.AssetID.eth, "ETH", "Ethereum", .major,
                coinGeckoId: "ethereum", role: role, amount: amount, usdValue: amount * 2900),
            position: PositionContext(
                positionId: position,
                positionType: protocolId == nil ? .idle : .lending,
                accountId: Fixture.degenAccount,
                chain: chain,
                protocolId: protocolId))
    }

    static func asset(
        _ id: UUID,
        _ symbol: String,
        coinGeckoId: String? = nil,
        onchainIdentity: OnchainTokenIdentity? = nil) -> AssetDetailAsset {
        AssetDetailAsset(
            id: id,
            symbol: symbol,
            name: symbol,
            category: .other,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity)
    }

    /// The fixture's account and protocol names: Main and Degen; Aave V3 and Lido.
    static func labels(
        _ inputs: [ValuationInput],
        accountNames: [UUID: String] = [Fixture.mainAccount: "Main", Fixture.degenAccount: "Degen"]) -> [UUID: AssetDetailRowLabels] {
        let protocolNames = ["aave-v3": "Aave V3", "lido": "Lido"]
        return Dictionary(uniqueKeysWithValues: inputs.map { input in
            (input.tokenId, AssetDetailRowLabels(
                accountName: input.position.accountId.flatMap { accountNames[$0] } ?? "?",
                protocolName: input.position.protocolId.flatMap { protocolNames[$0] }))
        })
    }

    static func page(
        _ asset: AssetDetailAsset,
        inputs: [ValuationInput],
        rate: Decimal = 1,
        settings: TokenDashboardSettings = .defaults,
        liveChanges24h: [String: Decimal] = Fixture.liveChanges24h,
        labels: [UUID: AssetDetailRowLabels]? = nil) -> AssetDetailPage {
        AssetDetailFeature.page(
            Fixture.context(rate: rate, settings: settings, inputs: inputs, liveChanges24h: liveChanges24h),
            asset: asset,
            labels: labels ?? Self.labels(inputs))
    }

    struct RowValue: Equatable {
        let id: UUID
        let state: TokenRowState
        let value: Decimal?
    }

    static func rows(_ page: AssetDetailPage) -> [RowValue] {
        page.rows.map { RowValue(id: $0.id, state: $0.state, value: $0.value) }
    }
}

struct AssetDetailSeamTests {
    typealias Fixture = PortfolioValuationFixture
    typealias Seam = AssetDetailSeamFixture

    // MARK: - Header (S7, V5, U3)

    /// V5: Σ value ÷ Σ amount over the counted valued tokens, 13,500 ÷ 4.5; the lead token (the
    /// 6000 wallet balance) gives the live source and its +25% fraction. The rate is applied once.
    @Test func `a held asset's header follows V5`() {
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant)
        let converted = Seam.page(Seam.eth, inputs: Seam.ethVariant, rate: Fixture.decimal("0.9"))

        #expect(page.header == RowPricing(price: 3000, source: .live, fraction24h: Fixture.decimal("0.25")))
        #expect(converted.header == RowPricing(price: 2700, source: .live, fraction24h: Fixture.decimal("0.25")))
    }

    /// S7: LINK has no live price; its newer close (16) values it and the historical +25% is its
    /// merged fraction. Today the header reads live changes only.
    @Test func `the header shows the merged historical fraction`() {
        let link = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.link }
        let page = Seam.page(Seam.asset(Fixture.AssetID.link, "LINK", coinGeckoId: "chainlink"), inputs: link)

        #expect(page.header == RowPricing(price: 16, source: .close, fraction24h: Fixture.decimal("0.25")))
    }

    /// V5: a manual lead has no fraction, even with a live fraction on file for its coin.
    @Test func `a manual price shows no fraction`() {
        let manual = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.manual }
        let page = Seam.page(
            Seam.asset(Fixture.AssetID.manual, "MNL", coinGeckoId: "manual-coin"),
            inputs: manual,
            liveChanges24h: Fixture.liveChanges24h.merging(["manual-coin": Fixture.decimal("0.1")]) { $1 })

        #expect(page.header == RowPricing(price: 2, source: .manual, fraction24h: nil))
    }

    /// U3: BAD is held and counted, but its onchain live price is implausible, so nothing is
    /// valued and there is no card. It never falls back to the market quote (10,000).
    @Test func `a held asset with nothing valued shows no card`() {
        let bad = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.bad }
        let page = Seam.page(Seam.asset(Fixture.AssetID.bad, "BAD", onchainIdentity: Fixture.badIdentity), inputs: bad)

        #expect(page.header == nil)
    }

    /// U3: an asset with no counted, non-ignored token shows `MarketPrices.quote` under its market
    /// price ID: the live price, else the latest close. Bitcoin is live, dogecoin has a close only,
    /// SOL holds only its reward, and DEGEN resolves through its identity mapping.
    @Test func `an unheld or reward-only asset shows the market quote`() {
        let solReward = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.sol && $0.token.role == .reward }
        let bitcoin = Seam.page(Seam.asset(Fixture.uuid(9701), "BTC", coinGeckoId: "bitcoin"), inputs: [])
        let convertedBitcoin = Seam.page(Seam.asset(Fixture.uuid(9701), "BTC", coinGeckoId: "bitcoin"), inputs: [], rate: Fixture.decimal("0.9"))
        let dogecoin = Seam.page(Seam.asset(Fixture.uuid(9702), "DOGE", coinGeckoId: "dogecoin"), inputs: [])
        let sol = Seam.page(Seam.asset(Fixture.AssetID.sol, "SOL", coinGeckoId: "solana"), inputs: solReward)
        let degen = Seam.page(Seam.asset(Fixture.AssetID.degen, "DEGEN", onchainIdentity: Fixture.degenIdentity), inputs: [])

        #expect(bitcoin.header == RowPricing(price: 60000, source: .live, fraction24h: Fixture.decimal("0.1")))
        #expect(convertedBitcoin.header == RowPricing(price: 54000, source: .live, fraction24h: Fixture.decimal("0.1")))
        #expect(dogecoin.header == RowPricing(price: Fixture.decimal("0.2"), source: .close, fraction24h: Fixture.decimal("-0.2")))
        #expect(sol.header == RowPricing(price: 150, source: .live, fraction24h: nil))
        #expect(degen.header == RowPricing(price: Fixture.decimal("0.01"), source: .live, fraction24h: nil))
    }

    /// U3: an ignored asset has no counted, non-ignored token, so it shows its market quote (SCAM
    /// live 50), while its row and totals count nothing.
    @Test func `an ignored asset shows the market quote`() {
        let scam = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.scam }
        let page = Seam.page(Seam.asset(Fixture.AssetID.scam, "SCAM", coinGeckoId: "scam-token"), inputs: scam)

        #expect(page.header == RowPricing(price: 50, source: .live, fraction24h: nil))
    }

    /// S7, U3: a held DEGEN prices through its identity mapping (degen-base, live 0.01), so the
    /// row, the total and the header share one price ID: 10,000 × 0.01.
    @Test func `a held mapped asset prices through its mapping`() {
        let degen = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.degen }
        let page = Seam.page(Seam.asset(Fixture.AssetID.degen, "DEGEN", onchainIdentity: Fixture.degenIdentity), inputs: degen)

        #expect(Seam.rows(page) == [.init(id: Fixture.tokenID(10), state: .counted, value: 100)])
        #expect(page.holdings.totalValue == 100)
        #expect(page.header == RowPricing(price: Fixture.decimal("0.01"), source: .live, fraction24h: nil))
    }

    // MARK: - Holdings (S7, A7, AGENT-DECIDED 13)

    /// A7: the total is Σ contributions, the amount the net of the counted tokens, and the
    /// accounts the two account IDs.
    @Test func `the holdings are the asset's net`() {
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant)

        #expect(page.holdings.totalAmount == Fixture.decimal("1.5"))
        #expect(page.holdings.accountCount == 2)
        #expect(page.holdings.totalValue == 4500)
    }

    /// AGENT-DECIDED 13: accounts are counted by ID, so two accounts sharing a name count twice.
    @Test func `the account count is the distinct account IDs`() {
        let labels = Seam.labels(Seam.ethVariant, accountNames: [Fixture.mainAccount: "Wallet", Fixture.degenAccount: "Wallet"])
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant, labels: labels)

        #expect(page.holdings.accountCount == 2)
    }

    /// AGENT-DECIDED 13, T4: an ignored asset's tokens add nothing to Total Amount or Total Value.
    @Test func `total amount leaves out ignored tokens`() {
        let scam = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.scam }
        let page = Seam.page(Seam.asset(Fixture.AssetID.scam, "SCAM", coinGeckoId: "scam-token"), inputs: scam)

        #expect(page.holdings.accountCount == 1)
        #expect(page.holdings.totalAmount == 0)
        #expect(page.holdings.totalValue == 0)
    }

    // MARK: - Per-chain breakdown (S7, F4, T2)

    /// S7, F4: each chain shows its net amount and net value; shares are net-value shares by largest
    /// remainder, a negative chain shows a negative share, and they sum to 100%. Today the borrow
    /// chain is dropped and shares are positive-amount shares.
    @Test func `each chain shows its net amount, net value and share`() {
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant)
        let expected = [
            AssetChainRow(name: "Ethereum", amount: Fixture.decimal("2.5"), value: 7500, share: Fixture.decimal("1.667")),
            AssetChainRow(name: "Arbitrum", amount: -1, value: -3000, share: Fixture.decimal("-0.667"))
        ]

        #expect(page.holdings.chains == expected)
        #expect(page.holdings.chains.compactMap(\.share).reduce(0, +) == 1)
    }

    /// F4: a net total that is not positive gives every chain "—" (7500 − 9000 = −1500).
    @Test func `chain shares show a dash when the total is not positive`() {
        let inputs = Seam.ethTokens + [Seam.arbitrumBorrow(amount: 3)]
        let page = Seam.page(Seam.eth, inputs: inputs)

        #expect(page.holdings.chains.map(\.name) == ["Ethereum", "Arbitrum"])
        #expect(page.holdings.chains.map(\.share) == [nil, nil])
    }

    /// S7: a chain holding only a reward counts nothing and vanishes; its row still shows in the
    /// table, not counted.
    @Test func `a reward-only chain vanishes`() {
        let reward = Seam.ethInput(Fixture.uuid(9502), role: .reward, amount: Fixture.decimal("0.1"), chain: .base, position: Fixture.uuid(9602))
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant + [reward])

        #expect(!page.holdings.chains.map(\.name).contains("Base"))
        #expect(page.holdings.chains.map(\.name) == ["Ethereum", "Arbitrum"])
    }

    /// C8: Asset Detail never hides a row, whatever the dashboard settings: a dust chain (0.0001 ETH
    /// on Optimism, $0.30) stays listed under the hiding defaults.
    @Test func `the per-chain breakdown never hides a dust chain`() {
        let dust = Seam.ethInput(
            Fixture.uuid(9503),
            role: .balance,
            amount: Fixture.decimal("0.0001"),
            chain: .optimism,
            position: Fixture.uuid(9603))
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant + [dust], settings: .defaults)

        #expect(page.holdings.chains.map(\.name).contains("Optimism"))
    }

    // MARK: - Token rows (S7, U4, T4, AGENT-DECIDED 13)

    /// S7, A7: rows are signed contributions, sorted by contribution, and they sum to the total.
    @Test func `token rows are signed and sum to the total`() {
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant)
        let expected: [Seam.RowValue] = [
            .init(id: Fixture.tokenID(2), state: .counted, value: 6000),
            .init(id: Fixture.tokenID(12), state: .counted, value: 3000),
            .init(id: Fixture.tokenID(13), state: .counted, value: -1500),
            .init(id: Seam.arbitrumBorrowID, state: .counted, value: -3000)
        ]

        #expect(Seam.rows(page) == expected)
        #expect(page.rows.compactMap(\.value).reduce(0, +) == page.holdings.totalValue)
    }

    /// A7, U4: with a reward (0.1 ETH on Base, its own 300) the counted rows' contributions still sum
    /// to the total; the not-counted row shows its own value, which stays out of that sum.
    @Test func `counted rows sum to the total beside a reward`() throws {
        let reward = Seam.ethInput(Fixture.uuid(9507), role: .reward, amount: Fixture.decimal("0.1"), chain: .base, position: Fixture.uuid(9607))
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant + [reward])
        let rewardRow = try #require(page.rows.first { $0.id == reward.tokenId })
        let counted = page.rows.filter { $0.state == .counted }

        #expect(page.holdings.totalValue == 4500)
        #expect(counted.map(\.id) == [Fixture.tokenID(2), Fixture.tokenID(12), Fixture.tokenID(13), Seam.arbitrumBorrowID])
        #expect(counted.compactMap(\.value).reduce(0, +) == page.holdings.totalValue)
        #expect(rewardRow.state == .notCounted)
        #expect(rewardRow.value == 300)
        #expect(page.rows.compactMap(\.value).reduce(0, +) == page.holdings.totalValue + 300)
    }

    /// T1 Units: the rate is applied once, to rows, total, chains and header alike.
    @Test func `the display rate is applied once`() {
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant, rate: Fixture.decimal("0.9"))

        #expect(page.rows.map(\.value) == [5400, 2700, -1350, -2700])
        #expect(page.holdings.totalValue == 4050)
        #expect(page.holdings.chains.map(\.value) == [6750, -2700])
    }

    /// U4: the stake counts its contribution; the reward shows its own value, not counted. An
    /// ignored token and an implausibly priced one show no value.
    @Test func `token rows show their U4 state`() {
        let sol = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.sol }
        let scam = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.scam }
        let bad = Fixture.inputs.filter { $0.token.assetId == Fixture.AssetID.bad }
        let solPage = Seam.page(Seam.asset(Fixture.AssetID.sol, "SOL", coinGeckoId: "solana"), inputs: sol)
        let scamPage = Seam.page(Seam.asset(Fixture.AssetID.scam, "SCAM", coinGeckoId: "scam-token"), inputs: scam)
        let badPage = Seam.page(Seam.asset(Fixture.AssetID.bad, "BAD", onchainIdentity: Fixture.badIdentity), inputs: bad)

        #expect(Seam.rows(solPage) == [
            .init(id: Fixture.tokenID(15), state: .counted, value: 1500),
            .init(id: Fixture.tokenID(16), state: .notCounted, value: 150)
        ])
        #expect(solPage.holdings.totalValue == 1500)
        #expect(Seam.rows(scamPage) == [.init(id: Fixture.tokenID(18), state: .ignored, value: nil)])
        #expect(Seam.rows(badPage) == [.init(id: Fixture.tokenID(8), state: .unpriced, value: nil)])
    }

    /// U4: a zero-amount balance counts nothing. Its row shows, not counted, at its own value of 0
    /// and sorts at contribution 0; the total, the amount and the chains leave it out.
    @Test func `a zero-amount token shows as not counted`() {
        let empty = Seam.ethInput(Fixture.uuid(9506), role: .balance, amount: 0, chain: .optimism, position: Fixture.uuid(9606))
        let page = Seam.page(Seam.eth, inputs: Seam.ethVariant + [empty])
        let expected: [Seam.RowValue] = [
            .init(id: Fixture.tokenID(2), state: .counted, value: 6000),
            .init(id: Fixture.tokenID(12), state: .counted, value: 3000),
            .init(id: empty.tokenId, state: .notCounted, value: 0),
            .init(id: Fixture.tokenID(13), state: .counted, value: -1500),
            .init(id: Seam.arbitrumBorrowID, state: .counted, value: -3000)
        ]

        #expect(Seam.rows(page) == expected)
        #expect(page.holdings.totalValue == 4500)
        #expect(page.holdings.totalAmount == Fixture.decimal("1.5"))
        #expect(page.holdings.chains.map(\.name) == ["Ethereum", "Arbitrum"])
    }

    /// AGENT-DECIDED 13: rows sort by contribution descending, then account name, then token ID. A
    /// reward (contribution 0) sits between the positives and the borrow.
    @Test func `token rows sort by contribution, then account name, then token ID`() {
        func otc(_ role: TokenRole, _ usdValue: Decimal) -> TokenEntry {
            Fixture.token(Fixture.AssetID.otc, "OTC", "Desk Token", .other, role: role, amount: 1, usdValue: usdValue)
        }
        let context = Fixture.context(tokens: [
            otc(.reward, 10),
            otc(.balance, 100),
            otc(.balance, 100),
            otc(.borrow, 50),
            otc(.balance, 100),
            otc(.balance, 200)
        ])
        let accounts = ["B", "B", "A", "A", "A", "B"]
        let labels = Dictionary(uniqueKeysWithValues: context.inputs.enumerated().map { index, input in
            (input.tokenId, AssetDetailRowLabels(accountName: accounts[index], protocolName: nil))
        })
        let page = AssetDetailFeature.page(context, asset: Seam.asset(Fixture.AssetID.otc, "OTC"), labels: labels)

        #expect(page.rows.map(\.id) == [5005, 5002, 5004, 5001, 5000, 5003].map(Fixture.uuid))
    }

    /// The row labels: account and protocol names from the label table, the position type as the
    /// context, the chain as the network; "Unknown", "Wallet" and "Off-chain" when missing.
    @Test func `rows carry their labels and defaults`() throws {
        let aave = Seam.ethInput(Fixture.uuid(9504), role: .supply, amount: 5, chain: .arbitrum, position: Fixture.uuid(9604), protocolId: "aave-v3")
        let offChain = ValuationInput(
            tokenId: Fixture.uuid(9505),
            token: Fixture.token(Fixture.AssetID.eth, "ETH", "Ethereum", .major, amount: 1, usdValue: 60000),
            position: PositionContext(positionId: Fixture.uuid(9605), positionType: .idle))
        let page = AssetDetailFeature.page(
            Fixture.context(inputs: [aave, offChain]),
            asset: Seam.eth,
            labels: [aave.tokenId: AssetDetailRowLabels(accountName: "DeFi Wallet", protocolName: "Aave V3")])

        let labelled = try #require(page.rows.first { $0.id == aave.tokenId })
        let unlabelled = try #require(page.rows.first { $0.id == offChain.tokenId })
        #expect([labelled.accountName, labelled.platformName, labelled.context, labelled.network] == [
            "DeFi Wallet",
            "Aave V3",
            "Lending",
            "Arbitrum"
        ])
        #expect([unlabelled.accountName, unlabelled.platformName, unlabelled.context, unlabelled.network] == [
            "Unknown",
            "Wallet",
            "Idle",
            "Off-chain"
        ])
    }
}
