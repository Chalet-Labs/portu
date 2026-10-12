import PortuCore
import PortuUI
import SwiftUI

enum OverviewHistoricalPriceChangeFeature {
    static func latestPrices(from prices: [HistoricalPriceEntry]) -> [String: Decimal] {
        latestCloses(from: prices).mapValues(\.price)
    }

    static func latestCloses(from prices: [HistoricalPriceEntry]) -> [String: HistoricalClose] {
        var latestByID: [String: HistoricalClose] = [:]
        for price in prices {
            guard
                let id = normalizedHistoricalPriceID(price.coinGeckoId),
                price.usdPrice > 0
            else { continue }
            let day = HistoricalPriceCalendar.utcStartOfDay(for: price.day)
            guard let existing = latestByID[id] else {
                latestByID[id] = HistoricalClose(day: day, price: price.usdPrice)
                continue
            }
            if day > existing.day || (day == existing.day && price.usdPrice > existing.price) {
                latestByID[id] = HistoricalClose(day: day, price: price.usdPrice)
            }
        }
        return latestByID
    }

    static func mergedPrices(
        live: [String: Decimal],
        historical: [String: Decimal]) -> [String: Decimal] {
        var merged: [String: Decimal] = [:]
        for (id, price) in historical where price > 0 {
            guard let normalizedID = normalizedHistoricalPriceID(id) else { continue }
            merged[normalizedID] = price
        }
        for (id, price) in live where price > 0 {
            guard let normalizedID = normalizedHistoricalPriceID(id) else { continue }
            merged[normalizedID] = price
        }
        return merged
    }

    private static func normalizedHistoricalPriceID(_ id: String?) -> String? {
        TokenIdentityMappingFeature.normalizedHistoricalPriceID(id)
    }
}

enum OverviewPositionChangeTone: Equatable {
    case favorable
    case unfavorable

    static func tone(for role: TokenRole, change: Decimal) -> OverviewPositionChangeTone {
        tone(isDebt: role.isBorrow, change: change)
    }

    static func tone(isDebt: Bool, change: Decimal) -> OverviewPositionChangeTone {
        if isDebt {
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
