#if DEBUG
    import ComposableArchitecture
    import Foundation
    @testable import Portu
    import PortuCore
    import SwiftData
    import Testing

    /// `/state/totals` (S11) over a small store, valued by hand in USD at noon on the fixture's today.
    ///
    /// | Token | Account | Amount | Synced | Valued |
    /// |---|---|---|---|---|
    /// | ETH | Wallet (active) | 2 | 5800 | 6000 (live 3000) |
    /// | DEGEN | Wallet | 10,000 | 95 | 100 (mapped to `degen-base`, live 0.01) |
    /// | LINK | Wallet | 10 | 120 (yesterday) | 150 (today's close 15); 120 with backfill off |
    /// | SCAM | Wallet | 1000 | 50,000 | 0 (ignored) |
    /// | ETH borrow | Wallet | 0.5 | 1450 | −1500 |
    /// | ETH reward | Wallet | 0.1 | 290 | 0 (not counted, and 0 in the sync-time total) |
    /// | GOLD | Vault (active, manual) | 2 | 400 | 500 (manual price 250) |
    /// | BTC | Cold (inactive) | 1 | 60,000 | 61,000 (live 61,000) |
    ///
    /// Wallet: valued 4750 (4720 with backfill off), sync-time total 54,565. Vault: 500 and 400.
    /// Active: valued 5250 (5220 with backfill off), sync-time total 54,965. Cold: 61,000 and 60,000.
    ///
    /// The wallet's idle position stores a `netUSDValue` of 54,015, not its tokens' 56,015, on
    /// purpose: a route that summed `netUSDValue` would report an active sync-time total of 52,965
    /// instead of 54,965.
    @MainActor
    struct DebugTotalsStore {
        typealias Fixture = PortfolioValuationFixture

        static let now = Fixture.noon(0)
        static let livePricesUSD: [String: Decimal] = [
            "ethereum": 3000,
            "degen-base": Fixture.decimal("0.01"),
            "bitcoin": 61000
        ]
        private static let degenContract = "0xde9e000000000000000000000000000000000de9"

        let container: ModelContainer
        let wallet: Account
        let vault: Account
        let cold: Account

        var context: ModelContext {
            container.mainContext
        }

        /// The route's market: the store's USD book at a display rate the totals must not apply.
        var market: DebugMarketInputs {
            DebugMarketInputs(livePricesUSD: Self.livePricesUSD, usdToDisplayRate: Fixture.decimal("0.9"))
        }

        /// `closes: false` leaves out the LINK close, so the totals do not depend on the backfill flag.
        /// `dustAndUnpriced: true` adds a wallet position the default display filter hides whole:
        /// DUST (amount 1, synced 0.5, no live price, so valued 0.5) and MYSTERY (amount 100, no
        /// price ID, synced 0, so unpriced). Active: valued 5250.5, sync-time total 54,965.5.
        init(closes: Bool = true, dustAndUnpriced: Bool = false) throws {
            self.container = try ModelContainer(
                for: Account.self, WalletAddress.self, Position.self, PositionToken.self, Asset.self,
                TokenPricingOverride.self, TokenIdentityMapping.self, HistoricalPricePoint.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = container.mainContext
            let syncedAt = Fixture.noon(-1)

            let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
            let degen = Asset(
                symbol: "DEGEN",
                name: "Degen",
                upsertChain: .degen,
                upsertContract: Self.degenContract,
                category: .meme)
            let link = Asset(symbol: "LINK", name: "Chainlink", coinGeckoId: "chainlink", category: .defi)
            let scam = Asset(symbol: "SCAM", name: "Scam", coinGeckoId: "scam-token", category: .meme)
            let gold = Asset(symbol: "GOLD", name: "Gold", category: .other)
            let btc = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major)

            self.wallet = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
            self.vault = Account(name: "Vault", kind: .manual, dataSource: .manual)
            self.cold = Account(name: "Cold", kind: .wallet, dataSource: .zerion, isActive: false)
            wallet.positions = [
                Position(
                    positionType: .idle,
                    chain: .ethereum,
                    netUSDValue: 54015,
                    tokens: [
                        PositionToken(role: .balance, amount: 2, usdValue: 5800, asset: eth),
                        PositionToken(role: .balance, amount: 10000, usdValue: 95, asset: degen),
                        PositionToken(role: .balance, amount: 10, usdValue: 120, asset: link),
                        PositionToken(role: .balance, amount: 1000, usdValue: 50000, asset: scam)
                    ],
                    syncedAt: syncedAt),
                Position(
                    positionType: .lending,
                    chain: .ethereum,
                    protocolName: "Aave V3",
                    netUSDValue: -1450,
                    tokens: [
                        PositionToken(role: .borrow, amount: Fixture.decimal("0.5"), usdValue: 1450, asset: eth),
                        PositionToken(role: .reward, amount: Fixture.decimal("0.1"), usdValue: 290, asset: eth)
                    ],
                    syncedAt: syncedAt)
            ]
            if dustAndUnpriced {
                wallet.positions.append(Self.dustAndUnpricedPosition(syncedAt: syncedAt, in: context))
            }
            vault.positions = [Position(
                positionType: .idle,
                netUSDValue: 400,
                tokens: [PositionToken(role: .balance, amount: 2, usdValue: 400, asset: gold)],
                syncedAt: syncedAt)]
            cold.positions = [Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 60000,
                tokens: [PositionToken(role: .balance, amount: 1, usdValue: 60000, asset: btc)],
                syncedAt: syncedAt)]

            for asset in [eth, degen, link, scam, gold, btc] {
                context.insert(asset)
            }
            for account in [wallet, vault, cold] {
                context.insert(account)
            }
            context.insert(TokenIdentityMapping(
                chain: .degen,
                contractAddress: Self.degenContract,
                coinGeckoId: "degen-base"))
            context.insert(TokenPricingOverride(assetId: scam.id, isIgnored: true))
            context.insert(TokenPricingOverride(assetId: gold.id, manualPriceUSD: 250))
            if closes {
                context.insert(HistoricalPricePoint(coinGeckoId: "chainlink", day: Fixture.day(0), price: 15))
            }
            try context.save()
        }

        private static func dustAndUnpricedPosition(syncedAt: Date, in context: ModelContext) -> Position {
            let dust = Asset(symbol: "DUST", name: "Dust", coinGeckoId: "dust-token", category: .meme)
            let mystery = Asset(symbol: "MYSTERY", name: "Mystery", category: .other)
            context.insert(dust)
            context.insert(mystery)
            return Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: Fixture.decimal("0.5"),
                tokens: [
                    PositionToken(role: .balance, amount: 1, usdValue: Fixture.decimal("0.5"), asset: dust),
                    PositionToken(role: .balance, amount: 100, usdValue: 0, asset: mystery)
                ],
                syncedAt: syncedAt)
        }

        /// The Overview headline over the same store, at a display rate of 1 so it reads in USD.
        func headline(isBackfillEnabled: Bool) throws -> OverviewHeadline {
            try OverviewFeature.headline(overviewContext(isBackfillEnabled: isBackfillEnabled))
        }

        /// The Overview's input over the same store, under the default dashboard settings: the active
        /// accounts' tokens, as the read model's headline takes them.
        func overviewContext(isBackfillEnabled: Bool) throws -> ValuationContext {
            let appState = AppState()
            appState.livePricesUSD = Self.livePricesUSD
            return try .activeAccounts(
                context.fetch(FetchDescriptor<Position>()).filter { $0.account?.isActive == true }.flatMap(\.tokens),
                overrides: context.fetch(FetchDescriptor<TokenPricingOverride>()),
                mappings: context.fetch(FetchDescriptor<TokenIdentityMapping>()),
                settings: .defaults,
                usdToDisplayRate: appState.currentUSDToDisplayRate,
                prices: .live(appState, historical: historical(isBackfillEnabled: isBackfillEnabled), includingLiveChanges: true))
        }

        /// Every account's Accounts balance over the same store, at a display rate of 1.
        func balances(isBackfillEnabled: Bool) throws -> [UUID: AccountBalance] {
            try AccountsFeature.balances(ValuationContext(
                inputs: AccountsFeature.valuationInputs(context.fetch(FetchDescriptor<Account>())),
                overrides: context.fetch(FetchDescriptor<TokenPricingOverride>()).map(TokenPricingOverrideSnapshot.init),
                mappings: context.fetch(FetchDescriptor<TokenIdentityMapping>()).map(TokenIdentityMappingSnapshot.init),
                settings: .defaults,
                usdToDisplayRate: 1,
                prices: ValuationPriceInputs(
                    livePricesUSD: Self.livePricesUSD,
                    historical: historical(isBackfillEnabled: isBackfillEnabled))))
        }

        private func historical(isBackfillEnabled: Bool) throws -> HistoricalMarketPrices {
            try HistoricalMarketPricesFeature.prices(
                from: context.fetch(FetchDescriptor<HistoricalPricePoint>()),
                isBackfillEnabled: isBackfillEnabled,
                now: Self.now)
        }
    }

    @MainActor
    struct DebugTotalsTests {
        private typealias Fixture = PortfolioValuationFixture

        /// A throwaway defaults suite holding the backfill flag, so no test reads the app's own.
        private final class BackfillDefaults {
            let defaults: UserDefaults
            private let suiteName = "DebugTotalsTests.\(UUID().uuidString)"

            init(isEnabled: Bool) throws {
                self.defaults = try #require(UserDefaults(suiteName: suiteName))
                defaults.set(isEnabled, forKey: HistoricalPriceBackfillSettings.isEnabledKey)
            }

            deinit {
                defaults.removePersistentDomain(forName: suiteName)
            }
        }

        private func totals(
            _ store: DebugTotalsStore,
            accountId: String? = nil,
            isBackfillEnabled: Bool = true) throws -> (statusCode: Int, json: [String: Any]) {
            let flag = try BackfillDefaults(isEnabled: isBackfillEnabled)
            let request = HTTPRequest(
                method: "GET",
                path: "/state/totals",
                queryParams: accountId.map { ["accountId": $0] } ?? [:])
            let response = DebugEndpoints.totals(
                context: store.context,
                request: request,
                market: store.market,
                defaults: flag.defaults,
                now: DebugTotalsStore.now)
            let json = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            return (response.statusCode, json)
        }

        @Test func `the active accounts' valued total is the Overview headline`() throws {
            let store = try DebugTotalsStore()
            let headline = try store.headline(isBackfillEnabled: true)
            #expect(headline.total == 5250)

            let response = try totals(store)

            #expect(response.statusCode == 200)
            #expect(response.json["valuedTotalUSD"] as? Double == headline.total.jsonDouble)
            #expect(response.json["rawSyncTotalUSD"] as? Double == 54965)
            #expect(response.json.keys.sorted() == ["rawSyncTotalUSD", "valuedTotalUSD"])
        }

        @Test func `an account's totals are its Accounts balance and provider total, inactive included`() throws {
            let store = try DebugTotalsStore()
            let balances = try store.balances(isBackfillEnabled: true)
            #expect(balances[store.wallet.id] == AccountBalance(balance: 4750, providerTotal: 54565))
            #expect(balances[store.vault.id] == AccountBalance(balance: 500, providerTotal: 400))
            #expect(balances[store.cold.id] == AccountBalance(balance: 61000, providerTotal: 60000))

            for account in [store.wallet, store.vault, store.cold] {
                let balance = try #require(balances[account.id])
                let response = try totals(store, accountId: account.id.uuidString)

                #expect(response.statusCode == 200)
                #expect(response.json["valuedTotalUSD"] as? Double == balance.balance.jsonDouble)
                #expect(response.json["rawSyncTotalUSD"] as? Double == balance.providerTotal.jsonDouble)
            }
        }

        /// I1: with backfill off no close is read, so LINK falls back to its sync value.
        @Test func `the closes are empty when backfill is off`() throws {
            let store = try DebugTotalsStore()
            #expect(try store.headline(isBackfillEnabled: false).total == 5220)

            let enabled = try totals(store, isBackfillEnabled: true)
            let disabled = try totals(store, isBackfillEnabled: false)

            #expect(enabled.json["valuedTotalUSD"] as? Double == 5250)
            #expect(disabled.json["valuedTotalUSD"] as? Double == 5220)
            #expect(disabled.json["rawSyncTotalUSD"] as? Double == 54965)
        }

        /// A7: the default filter hides DUST and MYSTERY from every list, but no total drops them.
        @Test func `the totals ignore the display filter that hides dust and unpriced rows`() throws {
            let store = try DebugTotalsStore(dustAndUnpriced: true)
            let overview = try store.overviewContext(isBackfillEnabled: true)
            #expect(overview.settings == .defaults)
            let hidden = DashboardList(
                overview.valuation().tokens,
                basis: .net,
                settings: overview.settings,
                groupedBy: \.token.assetId).hidden
            #expect(hidden.rowCount == 2)
            #expect(hidden.unpricedCount == 1)
            #expect(hidden.gross == Fixture.decimal("0.5"))
            let headline = try store.headline(isBackfillEnabled: true)
            #expect(headline.total == Fixture.decimal("5250.5"))

            let response = try totals(store)

            #expect(response.statusCode == 200)
            #expect(response.json["valuedTotalUSD"] as? Double == headline.total.jsonDouble)
            #expect(response.json["rawSyncTotalUSD"] as? Double == 54965.5)
        }

        @Test func `a malformed accountId is a bad request`() throws {
            let store = try DebugTotalsStore()

            let response = try totals(store, accountId: "not-a-uuid")

            #expect(response.statusCode == 400)
            #expect(response.json["error"] as? String == "Invalid accountId")
        }

        @Test func `an unknown accountId is not found`() throws {
            let store = try DebugTotalsStore()

            let response = try totals(store, accountId: UUID().uuidString)

            #expect(response.statusCode == 404)
            #expect(response.json["error"] as? String == "Account not found")
        }

        /// The route runs through `DebugServer` with the live book from the store. Without it ETH,
        /// DEGEN and the borrow would fall back to their sync values (5065).
        @Test func `the route reads the store's live book through the server`() async throws {
            let store = try DebugTotalsStore(closes: false)
            var state = AppFeature.State()
            state.selectedCurrency = .chf
            state.currentUSDToDisplayRate = Fixture.decimal("0.9")
            state.livePricesUSD = DebugTotalsStore.livePricesUSD
            let appStore = Store(initialState: state) {
                AppFeature()
            } withDependencies: {
                $0.priceService = PriceServiceClient(
                    fetchPrices: { _ in PriceUpdate(prices: [:], changes24h: [:]) },
                    fetchHistoricalPrices: { _, _ in [] },
                    invalidateCache: {})
            }
            let server = DebugServer(port: 0, modelContainer: store.container, store: appStore)
            try await server.start()
            defer { server.stop() }

            let port = try #require(server.listeningPort)
            let (data, response) = try await URLSession.shared.data(
                from: #require(URL(string: "http://127.0.0.1:\(port)/state/totals")))
            let httpResponse = try #require(response as? HTTPURLResponse)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

            #expect(httpResponse.statusCode == 200)
            #expect(json["valuedTotalUSD"] as? Double == 5220)
            #expect(json["rawSyncTotalUSD"] as? Double == 54965)
        }
    }
#endif
