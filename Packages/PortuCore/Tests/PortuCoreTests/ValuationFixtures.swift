import Foundation
import PortuCore

/// Shared builders for the valuation specs. Tokens default to a CoinGecko-only identity (no onchain
/// identity) synced at noon on `day(0)`; pass `syncedAt` and closes explicitly where the order matters.
enum ValuationFixtures {
    /// 2025-10-06 00:00 UTC.
    static let today = Date(timeIntervalSince1970: 1_759_708_800)

    static func day(_ offset: Int) -> Date {
        today.addingTimeInterval(TimeInterval(offset) * 86400)
    }

    static func noon(_ offset: Int) -> Date {
        day(offset).addingTimeInterval(12 * 3600)
    }

    static func token(
        _ symbol: String = "ETH",
        assetId: UUID = UUID(),
        name: String? = nil,
        category: AssetCategory = .other,
        portfolioCategory: PortfolioCategorySnapshot? = nil,
        coinGeckoId: String? = nil,
        onchainIdentity: OnchainTokenIdentity? = nil,
        role: TokenRole = .balance,
        amount: Decimal = 1,
        usdValue: Decimal = 0,
        syncedAt: Date? = noon(0)) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: name ?? symbol,
            category: category,
            portfolioCategory: portfolioCategory,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue,
            syncedAt: syncedAt)
    }

    static func input(
        _ token: TokenEntry,
        tokenId: UUID = UUID(),
        positionId: UUID = UUID(),
        positionType: PositionType = .idle,
        accountId: UUID? = nil,
        chain: Chain? = nil,
        protocolId: String? = nil) -> ValuationInput {
        ValuationInput(
            tokenId: tokenId,
            token: token,
            position: PositionContext(
                positionId: positionId,
                positionType: positionType,
                accountId: accountId,
                chain: chain,
                protocolId: protocolId))
    }

    static func market(
        live: [String: Decimal] = [:],
        closes: [String: HistoricalClose] = [:],
        changes: [String: Decimal] = [:]) -> MarketPrices {
        MarketPrices(liveUSD: live, closesUSD: closes, changes24h: changes)
    }

    static func close(_ price: Decimal, day offset: Int) -> HistoricalClose {
        HistoricalClose(day: day(offset), price: price)
    }

    static func closeRow(
        _ priceID: String,
        _ price: Decimal,
        day offset: Int,
        currency: FiatCurrency = .usd) -> HistoricalCloseRow {
        HistoricalCloseRow(priceID: priceID, day: day(offset), currency: currency, price: price)
    }

    static func valuation(
        _ inputs: [ValuationInput],
        market: MarketPrices = market(),
        overrides: [TokenPricingOverrideSnapshot] = [],
        mappings: [TokenIdentityMappingSnapshot] = []) -> PortfolioValuation {
        PortfolioValuation(inputs: inputs, market: market, overrides: overrides, mappings: mappings)
    }

    /// Values a single token in an idle position.
    static func valued(
        _ token: TokenEntry,
        market: MarketPrices = market(),
        overrides: [TokenPricingOverrideSnapshot] = [],
        mappings: [TokenIdentityMappingSnapshot] = []) -> ValuedToken {
        valuation([input(token)], market: market, overrides: overrides, mappings: mappings).tokens[0]
    }

    /// Tokens priced at exactly their sync value: `usdValue` with no live price or close.
    static func synced(
        _ symbol: String,
        _ usdValue: Decimal,
        assetId: UUID = UUID(),
        role: TokenRole = .balance,
        portfolioCategory: PortfolioCategorySnapshot? = nil) -> TokenEntry {
        token(
            symbol,
            assetId: assetId,
            portfolioCategory: portfolioCategory,
            role: role,
            amount: 1,
            usdValue: usdValue)
    }

    static func list<Key: Hashable & Sendable>(
        _ valuation: PortfolioValuation,
        _ basis: DashboardBasis,
        settings: TokenDashboardSettings = .defaults,
        by key: (ValuedToken) -> Key) -> DashboardList<Key> {
        DashboardList(valuation.tokens, basis: basis, settings: settings, groupedBy: key)
    }

    static func ignore(_ token: TokenEntry, alwaysShow: Bool = false) -> TokenPricingOverrideSnapshot {
        ignore(token.assetId, alwaysShow: alwaysShow)
    }

    static func ignore(_ assetId: UUID, alwaysShow: Bool = false) -> TokenPricingOverrideSnapshot {
        TokenPricingOverrideSnapshot(assetId: assetId, isIgnored: true, alwaysShow: alwaysShow)
    }

    static func manual(_ token: TokenEntry, price: Decimal) -> TokenPricingOverrideSnapshot {
        manual(token.assetId, price: price)
    }

    static func manual(_ assetId: UUID, price: Decimal) -> TokenPricingOverrideSnapshot {
        TokenPricingOverrideSnapshot(assetId: assetId, manualPriceUSD: price)
    }

    static func alwaysShow(_ token: TokenEntry) -> TokenPricingOverrideSnapshot {
        TokenPricingOverrideSnapshot(assetId: token.assetId, alwaysShow: true)
    }

    static func onchain(_ chain: Chain = .ethereum, _ contract: String = "0xabc") -> OnchainTokenIdentity {
        OnchainTokenIdentity(chain: chain, contractAddress: contract)
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    static let stablecoins = category(PortfolioCategoryDefaults.stablecoinsCategoryID)
    static let fiat = category(PortfolioCategoryDefaults.fiatCategoryID)
    static let eth = category(PortfolioCategoryDefaults.ethCategoryID)
    static let meme = category(PortfolioCategoryDefaults.memeCategoryID)

    private static func category(_ id: UUID) -> PortfolioCategorySnapshot {
        PortfolioCategoryDefaults.categorySnapshots.first { $0.id == id } ?? PortfolioCategoryDefaults.fallbackCategory
    }
}
