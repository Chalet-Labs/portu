import Foundation
import PortuCore

extension TokenSettingsRow {
    /// An asset row in the display currency. Every token of the row shares one asset, so its
    /// symbol, name, category and override come from any of them; ignore applies to all of them.
    init?(
        _ row: DashboardRow<UUID>,
        override: TokenPricingOverrideSnapshot?,
        currency: FiatCurrency,
        rate: Decimal) {
        guard let token = row.tokens.first?.token else { return nil }
        let isIgnored = row.tokens.contains { $0.rowState == .ignored }
        self.init(
            assetId: row.key,
            symbol: token.symbol,
            name: token.name,
            amount: row.totals.netAmount,
            value: isIgnored ? nil : row.displayValue(rate: rate),
            portfolioCategory: token.portfolioCategory,
            pricingSource: isIgnored ? nil : TokenPricingSource(row.pricing.source, status: row.status),
            status: row.status,
            alwaysShow: row.alwaysShow,
            isIgnored: isIgnored,
            coinGeckoId: TokenPricingOverrideFeature.resolvedCoinGeckoID(token: token, override: override),
            logoURL: token.logoURL,
            currency: currency,
            override: override)
    }
}

extension TokenPricingSource {
    /// The row's V5 source. With none, an all-unpriced row reads Unpriced; a not-counted row has none.
    init?(_ source: ValuationSource?, status: RowStatus) {
        switch source {
        case .manual: self = .manual
        case .live: self = .live
        case .close: self = .close
        case .sync: self = .syncTime
        case .unpriced, .ignored, nil:
            guard status == .unpriced else { return nil }
            self = .unpriced
        }
    }
}
