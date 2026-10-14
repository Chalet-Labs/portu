import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// The Accounts seam (S9, A6, A7, T2) over the shared fixture plus an inactive account. Every value
/// is worked out by hand in USD from the fixture table.
///
/// Main account: Main Wallet 7340.8, Aave V3 1499.6, Lido 1500 (the reward counts 0), Arbitrum
/// Vesting 90 and Scam Wallet 0 (ignored), so 10,430.4; its sync-time total is 64,999.4 (SCAM's
/// 50,000 and BAD's 5000 included). Degen account: DEGEN 100 + OTC 250 = 350, synced at 345.
/// Σ active = 10,780.4, the headline. The inactive Cold Wallet holds 1 ETH (synced 2900, live 3000)
/// and 100 ARB (synced 80, live 0.9): 3090, synced at 2980.
enum AccountsSeamFixture {
    typealias Fixture = PortfolioValuationFixture

    static let inactiveAccount = Fixture.uuid(203)
    static let exchangeAccount = Fixture.uuid(204)
    static let manualAccount = Fixture.uuid(205)

    static let coldWallet = PositionContext(
        positionId: Fixture.uuid(107),
        positionType: .idle,
        accountId: inactiveAccount,
        chain: .ethereum)

    static let inactiveTokens: [ValuationInput] = [
        ValuationInput(
            tokenId: Fixture.uuid(9101),
            token: Fixture.token(Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 1, usdValue: 2900),
            position: coldWallet),
        ValuationInput(
            tokenId: Fixture.uuid(9102),
            token: Fixture.token(Fixture.AssetID.arb, "ARB", "Arbitrum", .governance, coinGeckoId: "arbitrum", amount: 100, usdValue: 80),
            position: coldWallet)
    ]

    /// The fixture plus the inactive account. The Accounts input holds every account (S9); the
    /// fixture's own inputs are the active ones, which the headline values.
    static let inputs = Fixture.inputs + inactiveTokens

    static func balances(rate: Decimal = 1, inputs: [ValuationInput] = inputs) -> [UUID: AccountBalance] {
        AccountsFeature.balances(Fixture.context(rate: rate, inputs: inputs))
    }

    /// One token alone in a position of `account`, with no chain, as an exchange or a manual entry
    /// has.
    static func lone(_ token: TokenEntry, account: UUID) -> ValuationInput {
        ValuationInput(
            tokenId: Fixture.uuid(9200),
            token: token,
            position: PositionContext(positionId: Fixture.uuid(9201), positionType: .idle, accountId: account))
    }
}

struct AccountsSeamTests {
    private typealias Fixture = PortfolioValuationFixture
    private typealias Seam = AccountsSeamFixture

    /// "Number changes → Accounts": balance = Σ contributions at the live, manual, close or sync
    /// value, active account or not. The provider total stays the sync-time total (A6).
    @Test func `each account's balance is the sum of its own tokens' contributions`() {
        let balances = Seam.balances()

        #expect(balances.mapValues(\.balance) == [
            Fixture.mainAccount: Fixture.decimal("10430.4"),
            Fixture.degenAccount: 350,
            Seam.inactiveAccount: 3090
        ])
        #expect(balances.mapValues(\.providerTotal) == [
            Fixture.mainAccount: Fixture.decimal("64999.4"),
            Fixture.degenAccount: 345,
            Seam.inactiveAccount: 2980
        ])
    }

    /// "Number changes → Accounts": Σ active balances = the Overview total, at any rate. The
    /// inactive account still shows its own balance, outside that sum (A7).
    @Test(arguments: [Decimal(1), PortfolioValuationFixture.decimal("0.9")])
    func `active balances sum to the Overview headline`(rate: Decimal) {
        let balances = Seam.balances(rate: rate)
        let headline = OverviewFeature.headline(Fixture.context(rate: rate))
        let active = [Fixture.mainAccount, Fixture.degenAccount].compactMap { balances[$0]?.balance }

        #expect(active.count == 2)
        #expect(headline.total == Fixture.decimal("10780.4") * rate)
        #expect(active.reduce(0, +) == headline.total)
        #expect(balances[Seam.inactiveAccount]?.balance == 3090 * rate)
    }

    /// "Number changes → Accounts": ignored tokens count 0. The provider total keeps them (A6 has
    /// no ignore filter).
    @Test func `an ignored token counts 0`() {
        let scam = Fixture.token(Fixture.AssetID.scam, "SCAM", "Scam Token", .other, coinGeckoId: "scam-token", amount: 1000, usdValue: 50000)
        let balances = Seam.balances(inputs: [Seam.lone(scam, account: Fixture.mainAccount)])

        #expect(balances[Fixture.mainAccount]?.balance == 0)
        #expect(balances[Fixture.mainAccount]?.providerTotal == 50000)
    }

    /// "Number changes → Accounts": an implausible onchain price counts 0 (V1.4: live 10,000 × 100
    /// is 200 times the sync value, and there is no fallback to it).
    @Test func `an implausible onchain price counts 0`() {
        let bad = Fixture.token(
            Fixture.AssetID.bad, "BAD", "Bad Price", .other, onchainIdentity: Fixture.badIdentity, amount: 100, usdValue: 5000)
        let balances = Seam.balances(inputs: [Seam.lone(bad, account: Fixture.mainAccount)])

        #expect(balances[Fixture.mainAccount]?.balance == 0)
        #expect(balances[Fixture.mainAccount]?.providerTotal == 5000)
    }

    /// "Number changes → Accounts": Kraken goes from 0 to a live value. An exchange stores no sync
    /// value, so its 0.5 BTC is worth live 60,000 × 0.5.
    @Test func `an exchange token with no sync value takes its live value`() {
        let balances = Seam.balances(inputs: [Seam.lone(Self.krakenBTC, account: Seam.exchangeAccount)])

        #expect(balances[Seam.exchangeAccount]?.balance == 30000)
    }

    /// U6: an exchange reports no USD value at sync, so its row carries no provider total and shows
    /// no tooltip. The wallet and the manual account keep theirs (64,999.4 and the 2900 entry).
    @Test func `an exchange account's row has no provider total`() {
        let manualETH = ValuationInput(
            tokenId: Fixture.uuid(9210),
            token: Fixture.token(Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 1, usdValue: 2900),
            position: PositionContext(positionId: Fixture.uuid(9211), positionType: .idle, accountId: Seam.manualAccount))
        let balances = Seam.balances(inputs: Fixture.inputs + [Seam.lone(Self.krakenBTC, account: Seam.exchangeAccount), manualETH])
        let accounts: [(id: UUID, kind: AccountKind, source: DataSource)] = [
            (Fixture.mainAccount, .wallet, .zerion),
            (Seam.manualAccount, .manual, .manual),
            (Seam.exchangeAccount, .exchange, .exchange)
        ]

        let rows = AccountsFeature.mapAccountRows(from: accounts.map { account in
            let balance = balances[account.id] ?? .zero
            return AccountInput(
                id: account.id, name: account.kind.rawValue, kind: account.kind,
                exchangeType: account.kind == .exchange ? .kraken : nil, dataSource: account.source, group: nil, isActive: true,
                lastSyncError: nil, totalBalance: balance.balance, providerTotal: balance.providerTotal,
                firstAddress: nil)
        })

        #expect(rows.map(\.balance) == [Fixture.decimal("10430.4"), 3000, 30000])
        #expect(rows.map(\.providerTotal) == [Fixture.decimal("64999.4"), 2900, nil])
    }

    private static let krakenBTC = Fixture.token(
        Fixture.uuid(16), "BTC", "Bitcoin", .major, coinGeckoId: "bitcoin", amount: Fixture.decimal("0.5"), usdValue: 0)

    /// "Number changes → Accounts", new tooltip "Provider total at last sync": the sync-time total
    /// (A6) at the current rate, on a synced account and on a manual one (AGENT-DECIDED 12, narrowed
    /// by U6). The manual entry stored 1 ETH at 2900; ETH is now live at 3000.
    @Test func `the provider total is the sync-time total at the current rate`() {
        let rate = Fixture.decimal("0.9")
        let manualETH = Fixture.token(Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 1, usdValue: 2900)
        let synced = Seam.balances(rate: rate)
        let manual = Seam.balances(rate: rate, inputs: [Seam.lone(manualETH, account: Seam.manualAccount)])

        #expect(synced[Fixture.mainAccount]?.providerTotal == Fixture.decimal("58499.46"))
        #expect(manual[Seam.manualAccount]?.providerTotal == 2610)
        #expect(manual[Seam.manualAccount]?.balance == 2700)

        let help = AccountsFormat.providerTotalHelp(2610, code: "USD")
        #expect(AccountsFormat.providerTotalLabel == "Provider total at last sync")
        #expect(help == "Provider total at last sync: \(AccountsFormat.currency(2610, code: "USD"))")
    }

    /// S9: the input holds every account's tokens, the inactive Old Wallet's BTC included. The
    /// store's active wallet holds ETH 2 (synced 5800, live 3000) and DEGEN (synced 95, mapped,
    /// live 100); the rate is 0.9.
    @MainActor
    @Test func `the input covers inactive accounts from the store`() throws {
        let store = try OverviewModelWiringTests.Store()
        let accounts = try store.container.mainContext.fetch(FetchDescriptor<Account>())
        let active = try #require(accounts.first { $0.isActive })
        let inactive = try #require(accounts.first { !$0.isActive })
        let rate = OverviewModelWiringTests.rate

        let balances = AccountsFeature.balances(ValuationContext(
            inputs: AccountsFeature.valuationInputs(accounts),
            overrides: [],
            mappings: store.mappings.map(TokenIdentityMappingSnapshot.init),
            settings: .defaults,
            usdToDisplayRate: rate,
            prices: ValuationPriceInputs(livePricesUSD: store.appState.livePricesUSD)))

        #expect(balances[inactive.id] == AccountBalance(balance: 60000 * rate, providerTotal: 60000 * rate))
        #expect(balances[active.id]?.providerTotal == 5895 * rate)
        #expect(balances[active.id]?.balance == 6100 * rate)
    }
}
