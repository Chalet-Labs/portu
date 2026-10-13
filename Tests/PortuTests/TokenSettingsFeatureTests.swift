import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

struct TokenSettingsFeatureTests {
    @Test func `dashboard threshold uses strict less than so boundary value stays visible`() {
        let boundary = token(symbol: "BOUND", coinGeckoId: "bound", amount: 1, usdValue: 0)
        let prices: [String: Decimal] = ["bound": 1]
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)

        #expect(TokenSettingsFeature.isDashboardEligible(
            token: boundary,
            prices: prices,
            override: nil,
            settings: settings))
    }

    @Test func `dashboard threshold hides values strictly below the minimum when hide dust is on`() {
        let below = token(symbol: "BELOW", coinGeckoId: "below", amount: 1, usdValue: 0)
        let prices: [String: Decimal] = ["below": decimal("0.99")]
        let hideDust = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)
        let showDust = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: false)

        #expect(!TokenSettingsFeature.isDashboardEligible(token: below, prices: prices, override: nil, settings: hideDust))
        #expect(TokenSettingsFeature.isDashboardEligible(token: below, prices: prices, override: nil, settings: showDust))
    }

    @Test func `dashboard defaults exclude zero amount ignored unpriced and dust tokens`() {
        let visible = token(symbol: "VISIBLE", coinGeckoId: "visible", amount: 1, usdValue: 2)
        let zeroAmount = token(symbol: "ZERO", coinGeckoId: "zero", amount: 0, usdValue: 10)
        let ignored = token(symbol: "IGNORED", coinGeckoId: "ignored", amount: 1, usdValue: 10)
        let unpriced = token(symbol: "UNPRICED", amount: 1, usdValue: 0)
        let syncOnly = token(symbol: "SYNC", amount: 1, usdValue: 1000)
        let dust = token(symbol: "DUST", coinGeckoId: "dust", amount: 1, usdValue: 0.50)

        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: [visible, zeroAmount, ignored, unpriced, syncOnly, dust],
            prices: ["visible": 2, "zero": 10, "ignored": 10, "dust": 0.50],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true)
            ],
            settings: .defaults)

        #expect(eligible.map(\.symbol) == ["VISIBLE"])
    }

    /// Flipped: a sync-only token is valued at its sync value with the Sync-time source (spec S8,
    /// V1.5). Number changes → Token Settings: "sync-only tokens are valued with the Sync-time source".
    @Test func `settings rows value a token with no live or manual price at its sync value`() throws {
        let syncOnly = token(symbol: "SYNC", amount: 2, usdValue: 1000)

        let result = settingsResult(tokens: [syncOnly])

        let row = try #require(result.rows.first)
        #expect(row.value == 1000)
        #expect(row.pricingSource == .syncTime)
        #expect(row.status == .priced)
    }

    @Test func `manual price and always show make low value tokens dashboard eligible`() {
        let manual = token(symbol: "MANUAL", amount: 2, usdValue: 0)
        let pinned = token(symbol: "PINNED", coinGeckoId: "pinned", amount: 1, usdValue: 0.25)

        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: [manual, pinned],
            prices: ["pinned": 0.25],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: decimal("0.60")),
                TokenPricingOverrideSnapshot(assetId: pinned.assetId, alwaysShow: true)
            ],
            settings: .defaults)

        #expect(eligible.map(\.symbol) == ["MANUAL", "PINNED"])
    }

    @Test func `dashboard eligibility accepts a prebuilt override map`() {
        let manual = token(symbol: "MANUAL", amount: 2, usdValue: 0)
        let hidden = token(symbol: "HIDDEN", coinGeckoId: "hidden", amount: 1, usdValue: 10)
        let overrides = [
            TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: decimal("1.25")),
            TokenPricingOverrideSnapshot(assetId: hidden.assetId, isIgnored: true)
        ]
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)

        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: [manual, hidden],
            prices: ["hidden": 10],
            overrideMap: overrideMap,
            settings: .defaults)

        #expect(eligible.map(\.symbol) == ["MANUAL"])
        #expect(eligible.first?.usdValue == decimal("2.50"))
    }

    @Test func `manual price wins over live price and coin gecko override is applied`() throws {
        let mapped = token(symbol: "MAP", coinGeckoId: "old-map", amount: 2, usdValue: 0)
        let overrides = [
            TokenPricingOverrideSnapshot(
                assetId: mapped.assetId,
                manualPriceUSD: decimal("3.50"),
                coinGeckoIdOverride: "new-map")
        ]

        let result = settingsResult(
            tokens: [mapped],
            overrides: overrides,
            livePricesUSD: ["old-map": 1, "new-map": 2])

        let row = try #require(result.rows.first)
        #expect(row.value == 7)
        #expect(row.pricingSource == .manual)
        #expect(row.status == .priced)
        #expect(row.coinGeckoId == "new-map")
    }

    @Test func `identity mappings apply coingecko ids without writing user overrides`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let local = token(symbol: "LOCAL", amount: 2, usdValue: 4, onchainIdentity: identity)
        let mapping = TokenIdentityMappingSnapshot(
            identity: identity,
            coinGeckoId: " mapped-token ")

        let entries = TokenSettingsFeature.applyIdentityMappings(
            to: [local],
            mappings: [mapping],
            overrides: [])

        #expect(entries.first?.coinGeckoId == "mapped-token")
        #expect(entries.first?.onchainIdentity == identity)
    }

    @Test func `settings rows use Zerion live price for unmapped onchain tokens`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let local = token(symbol: "LOCAL", amount: 2, usdValue: 0, onchainIdentity: identity)

        let result = settingsResult(tokens: [local], livePricesUSD: [identity.historicalPriceID: decimal("1.50")])

        let row = try #require(result.rows.first)
        #expect(row.value == 3)
        #expect(row.pricingSource == .live)
        #expect(row.status == .priced)
    }

    @Test func `settings rows treat implausible onchain live prices as unpriced`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0x000000000000000000000000000000000000dead")
        let local = token(symbol: "LOCAL", amount: 1_000_000_000_000_000_000, usdValue: 5, onchainIdentity: identity)

        let result = settingsResult(tokens: [local], livePricesUSD: [identity.historicalPriceID: 1])

        let row = try #require(result.rows.first)
        // U4: an unpriced row is listed with no value.
        #expect(row.value == nil)
        #expect(row.pricingSource == .unpriced)
        #expect(row.status == .unpriced)
    }

    @Test func `settings filters classify rows by pricing and override state`() {
        let priced = token(symbol: "PRICED", coinGeckoId: "priced", amount: 1, usdValue: 2)
        let unpriced = token(symbol: "UNPRICED", amount: 1, usdValue: 0)
        let dust = token(symbol: "DUST", coinGeckoId: "dust", amount: 1, usdValue: 0.25)
        let ignored = token(symbol: "IGNORED", coinGeckoId: "ignored", amount: 1, usdValue: 10)
        let manual = token(symbol: "MANUAL", amount: 2, usdValue: 0)
        let mapped = token(symbol: "MAPPED", coinGeckoId: "old-map", amount: 1, usdValue: 0)

        let overrides = [
            TokenPricingOverrideSnapshot(assetId: ignored.assetId, isIgnored: true),
            TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 2),
            TokenPricingOverrideSnapshot(assetId: mapped.assetId, coinGeckoIdOverride: "new-map")
        ]
        let tokens = [priced, unpriced, dust, ignored, manual, mapped]

        let prices: [String: Decimal] = ["priced": 2, "dust": 0.25, "ignored": 10, "new-map": 3]
        let all = settingsResult(tokens: tokens, overrides: overrides, livePricesUSD: prices)

        // The status is F1's RowStatus (AGENT-DECIDED 11): Visible reads Priced.
        let statuses = Dictionary(uniqueKeysWithValues: all.rows.map { ($0.symbol, $0.status) })
        #expect(statuses["PRICED"] == .priced)
        #expect(statuses["UNPRICED"] == .unpriced)
        #expect(statuses["DUST"] == .dust)
        #expect(statuses["IGNORED"] == .ignored)
        #expect(statuses["MANUAL"] == .priced)
        #expect(statuses["MAPPED"] == .priced)
        #expect(all.counts.all == 6)
        #expect(all.counts.unpriced == 1)
        #expect(all.counts.belowThreshold == 1)
        #expect(all.counts.ignored == 1)
        #expect(all.counts.notCounted == 0)
        #expect(all.counts.manualPrice == 1)
        #expect(all.counts.mappedPriceSource == 1)

        let manualRows = settingsResult(tokens: tokens, overrides: overrides, livePricesUSD: prices, filter: .manualPrice)

        #expect(manualRows.rows.map(\.symbol) == ["MANUAL"])
    }

    @Test func `settings rows expose resolved portfolio category for category assignment`() throws {
        let category = try PortfolioCategorySnapshot(
            id: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
            name: "Majors",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let eth = token(
            symbol: "ETH",
            portfolioCategory: category,
            coinGeckoId: "ethereum",
            amount: 1,
            usdValue: 3500)

        let result = settingsResult(tokens: [eth], livePricesUSD: ["ethereum": 3500])

        let row = try #require(result.rows.first)
        #expect(row.portfolioCategory == category)
    }

    @Test func `settings rows net positive and borrow tokens for the same asset`() throws {
        let assetId = uuid(999)
        let supplied = token(
            assetId: assetId,
            symbol: "ETH",
            coinGeckoId: "ethereum",
            role: .supply,
            amount: 10,
            usdValue: 30000)
        let borrowed = token(
            assetId: assetId,
            symbol: "ETH",
            coinGeckoId: "ethereum",
            role: .borrow,
            amount: 2,
            usdValue: 6000)

        let result = settingsResult(tokens: [supplied, borrowed], livePricesUSD: ["ethereum": 3000])

        let row = try #require(result.rows.first)
        #expect(result.rows.count == 1)
        #expect(row.amount == 8)
        #expect(row.value == 24000)
    }

    @Test func `dashboard eligibility scales the usd threshold by the display rate for live prices`() {
        let small = token(symbol: "SML", coinGeckoId: "sml", amount: 1, usdValue: 0)
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)

        let eligible = TokenSettingsFeature.isDashboardEligible(
            token: small,
            prices: ["sml": decimal("0.6")],
            override: nil,
            settings: settings,
            usdToDisplayRate: decimal("0.5"))

        #expect(eligible)
    }

    @Test func `dashboard eligibility still treats values below the scaled threshold as dust`() {
        let small = token(symbol: "SML", coinGeckoId: "sml", amount: 1, usdValue: 0)
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)

        let eligible = TokenSettingsFeature.isDashboardEligible(
            token: small,
            prices: ["sml": decimal("0.4")],
            override: nil,
            settings: settings,
            usdToDisplayRate: decimal("0.5"))

        #expect(!eligible)
    }

    @Test func `dashboard eligible tokens list scales the threshold by the display rate`() {
        let live = token(symbol: "LIVE", coinGeckoId: "live", amount: 1, usdValue: 0)
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)

        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: [live],
            prices: ["live": decimal("0.6")],
            overrides: [],
            settings: settings,
            usdToDisplayRate: decimal("0.5"))

        #expect(eligible.map(\.symbol) == ["LIVE"])
    }

    @Test func `settings rows convert the manual usd price into the display currency`() throws {
        let manual = token(symbol: "MAN", amount: 2, usdValue: 0)
        let override = TokenPricingOverrideSnapshot(assetId: manual.assetId, manualPriceUSD: 10)

        let result = settingsResult(tokens: [manual], overrides: [override], rate: decimal("0.9"), currency: .eur)

        let row = try #require(result.rows.first)
        #expect(row.pricingSource == .manual)
        #expect(row.currency == .eur)
        #expect(row.value == decimal("18"))
    }

    /// Flipped: the live book is USD and goes through the rate once (spec I1, T1). Number changes →
    /// Token Settings: "Values, sources and statuses come from the shared valuation".
    @Test func `settings rows convert live usd prices into the display currency once`() throws {
        let live = token(symbol: "LIV", coinGeckoId: "liv", amount: 3, usdValue: 0)

        let result = settingsResult(tokens: [live], livePricesUSD: ["liv": decimal("5")], rate: decimal("0.9"), currency: .eur)

        let row = try #require(result.rows.first)
        #expect(row.pricingSource == .live)
        #expect(row.currency == .eur)
        #expect(row.value == decimal("13.5"))
    }

    /// Flipped: the dust threshold is a USD amount, never scaled by the rate (spec T1, F2.4), so a
    /// $0.75 token is dust at any display rate.
    @Test func `settings dust threshold stays usd at any display rate`() throws {
        let small = token(symbol: "SML", coinGeckoId: "sml", amount: 1, usdValue: 0)
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: true)

        let result = settingsResult(
            tokens: [small],
            settings: settings,
            livePricesUSD: ["sml": decimal("0.75")],
            rate: decimal("0.5"),
            currency: .eur)

        let row = try #require(result.rows.first)
        #expect(row.value == decimal("0.375"))
        #expect(row.status == .dust)
    }

    @Test func `currency formatter uses the display currency symbol`() {
        #expect(TokenSettingsFormat.currency(decimal("12.5"), currency: .usd) == "$ 12.5")
        #expect(TokenSettingsFormat.currency(decimal("12.5"), currency: .eur) == "€ 12.5")
        #expect(TokenSettingsFormat.currency(decimal("12.5"), currency: .chf) == "CHF 12.5")
    }

    /// The Token Settings seam over ad-hoc tokens in one wallet.
    private func settingsResult(
        tokens: [TokenEntry],
        overrides: [TokenPricingOverrideSnapshot] = [],
        settings: TokenDashboardSettings = .defaults,
        livePricesUSD: [String: Decimal] = [:],
        rate: Decimal = 1,
        currency: FiatCurrency = .default,
        filter: TokenSettingsFilter = .all) -> TokenSettingsResult {
        TokenSettingsFeature.result(
            PortfolioValuationFixture.context(
                tokens: tokens,
                overrides: overrides,
                settings: settings,
                rate: rate,
                livePricesUSD: livePricesUSD),
            filter: filter,
            searchText: "",
            currency: currency)
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        category: AssetCategory = .other,
        portfolioCategory: PortfolioCategorySnapshot? = nil,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: category,
            portfolioCategory: portfolioCategory,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()
    }
}
