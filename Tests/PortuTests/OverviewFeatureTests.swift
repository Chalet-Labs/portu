import Foundation
@testable import Portu
import PortuCore
import Testing

struct OverviewFeatureTests {
    @Test func `asset candidates are pre grouped by normalized coin gecko id`() throws {
        let preferred = asset(symbol: "AAVE", coinGeckoId: " aave ")
        let later = asset(symbol: "ZAAVE", coinGeckoId: "AAVE")

        let grouped = OverviewFeature.assetCandidatesByCoinGeckoId(from: [later, preferred])

        #expect(grouped.keys.sorted() == ["aave"])
        #expect(try #require(grouped["aave"]) == preferred)
    }

    @Test func `watchlist suggestions are deduplicated by normalized coin gecko id`() {
        let preferred = asset(symbol: "AAVE", coinGeckoId: " aave ")
        let duplicate = asset(symbol: "ZAAVE", coinGeckoId: "AAVE")
        let sol = asset(symbol: "SOL", coinGeckoId: "solana")

        let suggestions = OverviewFeature.watchlistSuggestions(
            assets: [duplicate, sol, preferred],
            watchlistIDs: ["solana"],
            query: "aave")

        #expect(suggestions == [preferred])
    }

    @MainActor
    @Test func `asset candidates use coin gecko overrides`() throws {
        let assetId = UUID()
        let asset = Asset(id: assetId, symbol: "LOCAL", name: "Local", category: .other)

        let candidates = OverviewAssetCandidate.fromAssets(
            [asset],
            overrides: [
                TokenPricingOverrideSnapshot(assetId: assetId, coinGeckoIdOverride: " Local-Token ")
            ])

        let candidate = try #require(candidates.first)
        #expect(candidate.coinGeckoId == "local-token")
        #expect(candidate.symbol == "LOCAL")
    }

    @Test func `price display uses compact dollar prefix and trims asset labels`() throws {
        #expect(OverviewPriceDisplay.assetLabel("wrappedsteth") == "wrappe")
        #expect(OverviewPriceDisplay.assetLabel("BTC") == "BTC")

        let price = try OverviewPriceDisplay.price(#require(Decimal(
            string: "2866.478",
            locale: Locale(identifier: "en_US_POSIX"))))
        #expect(price.hasPrefix("$ "))
        #expect(!price.contains("US$"))
        #expect(!price.contains("US $"))
    }

    @Test func `price display keeps precision for very small assets`() throws {
        let price = try OverviewPriceDisplay.price(#require(Decimal(
            string: "0.00000012",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(price == "$ 0.00000012")
    }

    @Test func `overview currency display uses dollar prefix and compact huge values`() throws {
        let normal = try OverviewPriceDisplay.currency(#require(Decimal(
            string: "8889",
            locale: Locale(identifier: "en_US_POSIX"))))
        let huge = try OverviewPriceDisplay.currency(#require(Decimal(
            string: "-64842460574880",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(normal == "$ 8,889")
        #expect(huge == "-$ 64.8T")
        #expect(!normal.contains("US$"))
        #expect(!normal.contains("'"))
    }

    @Test func `overview axis currency display uses fixed dollar formatting`() {
        let label = OverviewPriceDisplay.axisCurrency(20000)

        #expect(label == "$ 20,000")
        #expect(!label.contains("US$"))
        #expect(!label.contains("'"))
    }

    @Test func `overview currency display supports eur and chf prefixes`() throws {
        let eur = try OverviewPriceDisplay.currency(#require(Decimal(
            string: "8889",
            locale: Locale(identifier: "en_US_POSIX"))), currencyCode: "EUR")
        let chf = OverviewPriceDisplay.axisCurrency(-20000, currencyCode: "CHF")

        #expect(eur == "€ 8,889")
        #expect(chf == "-CHF 20,000")
    }

    @Test func `overview amount display compacts very large token balances`() throws {
        let amount = try OverviewPriceDisplay.amount(#require(Decimal(
            string: "9990000000000",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(amount == "9.99T")
    }

    @Test func `price countdown derives remaining seconds from last update`() {
        let lastUpdate = Date(timeIntervalSince1970: 100)

        #expect(OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: lastUpdate,
            refreshInterval: 60,
            now: Date(timeIntervalSince1970: 112.2)) == 48)
        #expect(OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: lastUpdate,
            refreshInterval: 60,
            now: Date(timeIntervalSince1970: 170)) == 0)
        #expect(OverviewPriceCountdown.secondsRemaining(
            lastPriceUpdate: nil,
            refreshInterval: 60,
            now: lastUpdate) == 60)
    }

    @Test func `overview sync button uses compact reference metrics`() {
        #expect(DashboardSyncButtonStyleMetrics.iconName == "arrow.triangle.2.circlepath")
        #expect(DashboardSyncButtonStyleMetrics.height == 30)
        #expect(DashboardSyncButtonStyleMetrics.cornerRadius == 6)
        #expect(DashboardSyncButtonStyleMetrics.horizontalPadding == 11)
    }

    @Test func `watchlist persistence keeps order and uniqueness`() {
        let encoded = OverviewWatchlistStore.encode(["bitcoin", "ethereum", "bitcoin", "solana"])
        #expect(OverviewWatchlistStore.decode(encoded) == ["bitcoin", "ethereum", "solana"])

        let added = OverviewWatchlistStore.add("ethereum", to: ["bitcoin"])
        #expect(added == ["bitcoin", "ethereum"])

        let duplicate = OverviewWatchlistStore.add("bitcoin", to: added)
        #expect(duplicate == added)

        let removed = OverviewWatchlistStore.remove("bitcoin", from: duplicate)
        #expect(removed == ["ethereum"])
    }

    @Test func `token change ignores implausible onchain live prices`() {
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xBad")
        let local = token(symbol: "BAD", amount: 1_000_000, usdValue: 10, onchainIdentity: identity)

        let change = OverviewPositionPricing.change24h(
            token: local,
            prices: [identity.historicalPriceID: 1_000_000],
            changes24h: [identity.historicalPriceID: 0.10],
            override: nil)

        #expect(change == 0)
    }

    @Test func `overview position visibility excludes ignored dashboard tokens`() {
        let hidden = token(symbol: "HIDDEN", coinGeckoId: "hidden", amount: 1, usdValue: 10)
        let overrideMap = TokenSettingsFeature.overridesByAssetId([
            TokenPricingOverrideSnapshot(assetId: hidden.assetId, isIgnored: true)
        ])

        #expect(!OverviewPositionVisibility.isVisible(
            token: hidden,
            prices: ["hidden": 10],
            overrideMap: overrideMap,
            settings: .defaults))
    }

    @Test func `position pricing normalizes coin gecko ids`() {
        #expect(OverviewPositionPricing.price(
            coinGeckoId: " Ethereum ",
            amount: 2,
            usdValue: 10,
            prices: ["ethereum": 3000]) == 3000)
        #expect(OverviewPositionPricing.tokenValue(
            coinGeckoId: " Ethereum ",
            amount: 2,
            usdValue: 10,
            prices: ["ethereum": 3000]) == 6000)
        #expect(OverviewPositionPricing.change24h(
            coinGeckoId: " Ethereum ",
            amount: 2,
            prices: ["ethereum": 3000],
            changes24h: ["ethereum": 0.05]) == 300)
    }

    @Test func `borrow change tone treats increasing liabilities as unfavorable`() {
        #expect(OverviewPositionChangeTone.tone(for: .borrow, change: 10) == .unfavorable)
        #expect(OverviewPositionChangeTone.tone(for: .borrow, change: -10) == .favorable)
        #expect(OverviewPositionChangeTone.tone(for: .balance, change: 10) == .favorable)
        #expect(OverviewPositionChangeTone.tone(for: .balance, change: -10) == .unfavorable)
    }

    @Test func `overview labels describe merged rows and named layout constants`() {
        #expect(PriceWatchlistText.priceHeaderTitle == "Portfolio + Watchlist")
        #expect(TopAssetsDonutText.seeAllButtonTitle == "See all →")
        #expect(OverviewLayout.inspectorRailWidthAdjustment == 22)
    }

    @Test func `overview major label uses configured category names`() {
        let customBTC = PortfolioCategorySnapshot(
            id: PortfolioCategoryDefaults.btcCategoryID,
            name: "Majors",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false)
        let customETH = PortfolioCategorySnapshot(
            id: PortfolioCategoryDefaults.ethCategoryID,
            name: "L1s",
            sortOrder: 1,
            semanticRole: .normal,
            isSystemRequired: false)

        #expect(OverviewSummaryLabels.majorCategoryTitle(categories: [customETH, customBTC]) == "Majors / L1s")
        #expect(OverviewSummaryLabels.majorCategoryTitle(categories: []) == "Majors")
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        name: String? = nil,
        category: AssetCategory = .major,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil,
        logoURL: String? = nil) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: name ?? symbol,
            category: category,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue,
            logoURL: logoURL)
    }

    private func asset(
        id: UUID = UUID(),
        symbol: String,
        category: AssetCategory = .major,
        coinGeckoId: String,
        logoURL: String? = nil) -> OverviewAssetCandidate {
        OverviewAssetCandidate(
            id: id,
            symbol: symbol,
            name: symbol,
            category: category,
            coinGeckoId: coinGeckoId,
            logoURL: logoURL)
    }
}
