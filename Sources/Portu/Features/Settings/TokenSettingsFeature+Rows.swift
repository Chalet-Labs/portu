import Foundation
import PortuCore

extension TokenSettingsRow {
    /// An asset row in the display currency. Every token of the row shares one asset, so its
    /// symbol, name, category and override come from any of them; ignore applies to all of them.
    /// Ignored and unpriced rows have no value; a not-counted row shows its tokens' own value, which
    /// counts nowhere (U4, S8). The amount covers the tokens the row describes: the counted ones on a
    /// counted row, every token on an ignored or not-counted row.
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
            amount: Self.amount(of: row, isIgnored: isIgnored),
            value: Self.value(of: row, isIgnored: isIgnored, rate: rate),
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

    /// Borrows subtract, as in `ValuationTotals.netAmount`; rewards add.
    private static func amount(of row: DashboardRow<UUID>, isIgnored: Bool) -> Decimal {
        guard isIgnored || row.status == .notCounted else { return row.totals.netAmount }
        return row.tokens.reduce(0) { sum, token in
            sum + (token.token.role.isBorrow ? -token.token.amount : token.token.amount)
        }
    }

    private static func value(of row: DashboardRow<UUID>, isIgnored: Bool, rate: Decimal) -> Decimal? {
        if isIgnored {
            return nil
        }
        switch row.status {
        case .notCounted:
            return row.tokens.reduce(0) { $0 + $1.display(rate: rate).value }
        case .ignored, .unpriced:
            return nil
        case .dust, .priced:
            return row.displayValue(rate: rate)
        }
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
