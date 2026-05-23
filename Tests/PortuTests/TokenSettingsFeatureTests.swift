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

    @Test func `settings rows treat sync time value without live or manual price as unpriced`() throws {
        let syncOnly = token(symbol: "SYNC", amount: 2, usdValue: 1000)

        let result = TokenSettingsFeature.rows(
            tokens: [syncOnly],
            prices: [:],
            overrides: [],
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

        let row = try #require(result.rows.first)
        #expect(row.price == 0)
        #expect(row.value == 0)
        #expect(row.pricingSource == .unpriced)
        #expect(row.visibilityStatus == .unpriced)
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

        let entries = TokenSettingsFeature.applyPriceOverrides(to: [mapped], overrides: overrides)
        let result = TokenSettingsFeature.rows(
            tokens: [mapped],
            prices: ["old-map": 1, "new-map": 2],
            overrides: overrides,
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

        let row = try #require(result.rows.first)
        #expect(entries.first?.coinGeckoId == "new-map")
        #expect(row.price == decimal("3.50"))
        #expect(row.value == 7)
        #expect(row.pricingSource == .manual)
        #expect(row.visibilityStatus == .visible)
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

    @Test func `settings rows use zapper live price for unmapped onchain tokens`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xLocal")
        let local = token(symbol: "LOCAL", amount: 2, usdValue: 0, onchainIdentity: identity)

        let result = TokenSettingsFeature.rows(
            tokens: [local],
            prices: [identity.historicalPriceID: decimal("1.50")],
            overrides: [],
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

        let row = try #require(result.rows.first)
        #expect(row.price == decimal("1.50"))
        #expect(row.value == 3)
        #expect(row.pricingSource == .live)
        #expect(row.visibilityStatus == .visible)
    }

    @Test func `settings rows treat implausible onchain live prices as unpriced`() throws {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0x000000000000000000000000000000000000dead")
        let local = token(symbol: "LOCAL", amount: 1_000_000_000_000_000_000, usdValue: 5, onchainIdentity: identity)

        let result = TokenSettingsFeature.rows(
            tokens: [local],
            prices: [identity.historicalPriceID: 1],
            overrides: [],
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

        let row = try #require(result.rows.first)
        #expect(row.price == 0)
        #expect(row.value == 0)
        #expect(row.pricingSource == .unpriced)
        #expect(row.visibilityStatus == .unpriced)
    }

    @Test func `settings rows apply search and cap displayed matches to one hundred`() {
        let tokens = (0 ..< 120).map { index in
            token(
                assetId: uuid(index),
                symbol: String(format: "ROW%03d", index),
                coinGeckoId: "row-\(index)",
                amount: 1,
                usdValue: 2)
        }
        let prices = Dictionary(uniqueKeysWithValues: tokens.compactMap { token in
            token.coinGeckoId.map { ($0, Decimal(2)) }
        })

        let result = TokenSettingsFeature.rows(
            tokens: tokens,
            prices: prices,
            overrides: [],
            settings: .defaults,
            filter: .all,
            searchText: "row",
            limit: 100)

        #expect(result.totalMatches == 120)
        #expect(result.rows.count == 100)
        #expect(result.rows.first?.symbol == "ROW000")
        #expect(result.rows.last?.symbol == "ROW099")
        #expect(result.counts.all == 120)
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

        let all = TokenSettingsFeature.rows(
            tokens: tokens,
            prices: ["priced": 2, "dust": 0.25, "ignored": 10, "new-map": 3],
            overrides: overrides,
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

        let statuses = Dictionary(uniqueKeysWithValues: all.rows.map { ($0.symbol, $0.visibilityStatus) })
        #expect(statuses["PRICED"] == .visible)
        #expect(statuses["UNPRICED"] == .unpriced)
        #expect(statuses["DUST"] == .dust)
        #expect(statuses["IGNORED"] == .ignored)
        #expect(statuses["MANUAL"] == .visible)
        #expect(statuses["MAPPED"] == .visible)
        #expect(all.counts.all == 6)
        #expect(all.counts.unpriced == 1)
        #expect(all.counts.belowThreshold == 1)
        #expect(all.counts.ignored == 1)
        #expect(all.counts.manualPrice == 1)
        #expect(all.counts.mappedPriceSource == 1)

        let manualRows = TokenSettingsFeature.rows(
            tokens: tokens,
            prices: ["priced": 2, "dust": 0.25, "ignored": 10, "new-map": 3],
            overrides: overrides,
            settings: .defaults,
            filter: .manualPrice,
            searchText: "",
            limit: 100)

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

        let result = TokenSettingsFeature.rows(
            tokens: [eth],
            prices: ["ethereum": 3500],
            overrides: [],
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

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

        let result = TokenSettingsFeature.rows(
            tokens: [supplied, borrowed],
            prices: ["ethereum": 3000],
            overrides: [],
            settings: .defaults,
            filter: .all,
            searchText: "",
            limit: 100)

        let row = try #require(result.rows.first)
        #expect(result.rows.count == 1)
        #expect(row.amount == 8)
        #expect(row.price == 3000)
        #expect(row.value == 24000)
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
