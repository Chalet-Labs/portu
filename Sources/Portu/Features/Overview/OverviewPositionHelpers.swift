import PortuCore
import PortuUI
import SwiftUI

enum OverviewPositionPricing {
    static func price(
        coinGeckoId: String?,
        amount: Decimal,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        normalizedPrice(coinGeckoId: coinGeckoId, prices: prices)
            ?? (amount > 0 ? usdValue / amount : 0)
    }

    static func tokenValue(
        coinGeckoId: String?,
        amount: Decimal,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        normalizedPrice(coinGeckoId: coinGeckoId, prices: prices).map { amount * $0 }
            ?? usdValue
    }

    static func change24h(
        coinGeckoId: String?,
        amount: Decimal,
        prices: [String: Decimal],
        changes24h: [String: Decimal]) -> Decimal {
        guard
            let coinGeckoId = OverviewWatchlistStore.normalizedID(coinGeckoId),
            let price = prices[coinGeckoId],
            let changePercent = changes24h[coinGeckoId]
        else {
            return 0
        }
        return amount * price * changePercent
    }

    private static func normalizedPrice(
        coinGeckoId: String?,
        prices: [String: Decimal]) -> Decimal? {
        OverviewWatchlistStore.normalizedID(coinGeckoId).flatMap { prices[$0] }
    }
}

enum OverviewPositionChangeTone: Equatable {
    case favorable
    case unfavorable

    static func tone(for role: TokenRole, change: Decimal) -> OverviewPositionChangeTone {
        if role.isBorrow {
            return change <= 0 ? .favorable : .unfavorable
        }
        return change >= 0 ? .favorable : .unfavorable
    }

    @MainActor
    var color: Color {
        switch self {
        case .favorable:
            PortuTheme.dashboardSuccess
        case .unfavorable:
            PortuTheme.dashboardWarning
        }
    }
}
