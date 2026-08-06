import Foundation
import PortuCore

struct LocalPortfolioValueObservation: Equatable {
    let timestamp: Date
    let usdValue: Decimal
    let isFresh: Bool
}

enum PortfolioHistorySource: String, Equatable {
    case zerion
    case local
}

struct PortfolioHistoryPoint: Equatable {
    let timestamp: Date
    let usdValue: Decimal
    let source: PortfolioHistorySource
    let isReliable: Bool
}

struct ConvertedProviderPortfolioValuePoint: Equatable {
    let timestamp: Date
    let value: Decimal
}

struct ProviderHistoryConversionResult: Equatable {
    let points: [ConvertedProviderPortfolioValuePoint]
    let historicalFXUnavailableBefore: Date?
}

struct ProviderHistoryMergeContext {
    let local: [LocalPortfolioValueObservation]
    let selectedAccountID: UUID?
    let startDate: Date?
}

enum ProviderPortfolioHistory {
    static func refreshFailure(
        for points: [ProviderPortfolioValueDTO],
        status: PortfolioAnalyticsLoadStatus) -> PortfolioAnalyticsFailure? {
        guard points.isEmpty == false, case let .failed(failure) = status else {
            return nil
        }
        return failure
    }

    static func disclosure(
        for points: [ProviderPortfolioValueDTO]) -> String? {
        guard points.isEmpty == false else { return nil }
        if points.contains(where: { $0.coverage == .providerReported }) {
            return "Zerion history · provider-reported position coverage may be incomplete"
        }
        return "Zerion history · historical complex DeFi coverage may be incomplete"
    }

    static func renderedProviderPoints(
        for points: [ProviderPortfolioValueDTO],
        renderedTimestamps: Set<Date>) -> [ProviderPortfolioValueDTO] {
        points.filter { renderedTimestamps.contains($0.timestamp) }
    }

    static func merge(
        provider: [ProviderPortfolioValueDTO],
        local: [LocalPortfolioValueObservation],
        selectedAccountID: UUID?,
        startDate: Date? = nil) -> [PortfolioHistoryPoint] {
        let localByDay = latestLocalByDay(local)
        let authorityDay = local
            .filter(\.isFresh)
            .map { HistoricalPriceCalendar.utcStartOfDay(for: $0.timestamp) }
            .min()
        let providerPrefix = retainedProviderPoints(
            provider,
            local: local,
            selectedAccountID: selectedAccountID,
            startDate: startDate)
        let merged: [PortfolioHistoryPoint]
        guard selectedAccountID != nil else {
            merged = localByDay.map {
                PortfolioHistoryPoint(
                    timestamp: $0.timestamp,
                    usdValue: $0.usdValue,
                    source: .local,
                    isReliable: $0.isFresh)
            }
            return filtered(merged, startingAt: startDate)
        }

        if let authorityDay {
            let providerPoints = providerPrefix.map {
                PortfolioHistoryPoint(
                    timestamp: $0.timestamp,
                    usdValue: $0.usdValue,
                    source: .zerion,
                    isReliable: true)
            }
            let localSuffix = localByDay
                .filter { HistoricalPriceCalendar.utcStartOfDay(for: $0.timestamp) >= authorityDay }
                .map {
                    PortfolioHistoryPoint(
                        timestamp: $0.timestamp,
                        usdValue: $0.usdValue,
                        source: .local,
                        isReliable: $0.isFresh)
                }
            merged = (providerPoints + localSuffix).sorted {
                if $0.timestamp != $1.timestamp {
                    return $0.timestamp < $1.timestamp
                }
                return $0.source.rawValue < $1.source.rawValue
            }
        } else {
            merged = providerPrefix.map {
                PortfolioHistoryPoint(
                    timestamp: $0.timestamp,
                    usdValue: $0.usdValue,
                    source: .zerion,
                    isReliable: true)
            }
        }
        return filtered(merged, startingAt: startDate)
    }

    static func convertProviderHistory(
        _ points: [ProviderPortfolioValueDTO],
        mergeContext: ProviderHistoryMergeContext,
        currency: FiatCurrency,
        historicalRatesByDay: [Date: Decimal]) -> ProviderHistoryConversionResult {
        convertProviderHistory(
            retainedProviderPoints(
                points,
                local: mergeContext.local,
                selectedAccountID: mergeContext.selectedAccountID,
                startDate: mergeContext.startDate),
            currency: currency,
            historicalRatesByDay: historicalRatesByDay)
    }

    static func convertProviderHistory(
        _ points: [ProviderPortfolioValueDTO],
        currency: FiatCurrency,
        historicalRatesByDay: [Date: Decimal]) -> ProviderHistoryConversionResult {
        let sorted = latestProviderByDay(points)
        guard currency != .usd else {
            return ProviderHistoryConversionResult(
                points: sorted.map {
                    ConvertedProviderPortfolioValuePoint(timestamp: $0.timestamp, value: $0.usdValue)
                },
                historicalFXUnavailableBefore: nil)
        }

        let normalizedRates = Dictionary(
            historicalRatesByDay.map {
                (HistoricalPriceCalendar.utcStartOfDay(for: $0.key), $0.value)
            },
            uniquingKeysWith: { _, latest in latest })
        var suffixStart = 0
        for (index, point) in sorted.enumerated() where normalizedRates[point.day] == nil {
            suffixStart = index + 1
        }
        let suffix = sorted.dropFirst(suffixStart)
        let converted = suffix.compactMap { point -> ConvertedProviderPortfolioValuePoint? in
            guard let rate = normalizedRates[point.day] else { return nil }
            return ConvertedProviderPortfolioValuePoint(
                timestamp: point.timestamp,
                value: point.usdValue * rate)
        }
        return ProviderHistoryConversionResult(
            points: converted,
            historicalFXUnavailableBefore: suffixStart > 0 ? converted.first?.timestamp : nil)
    }

    static func estimatesOutsideProviderCoverage(
        _ estimates: [HistoricalPortfolioValuePoint],
        providerDates: [Date]) -> [HistoricalPortfolioValuePoint] {
        guard
            let firstProviderDate = providerDates.min(),
            let lastProviderDate = providerDates.max()
        else {
            return estimates
        }
        let firstProviderDay = HistoricalPriceCalendar.utcStartOfDay(for: firstProviderDate)
        let lastProviderDay = HistoricalPriceCalendar.utcStartOfDay(for: lastProviderDate)
        return estimates.filter {
            let day = HistoricalPriceCalendar.utcStartOfDay(for: $0.date)
            return day < firstProviderDay || day > lastProviderDay
        }
    }

    static func retainedProviderPoints(
        _ provider: [ProviderPortfolioValueDTO],
        local: [LocalPortfolioValueObservation],
        selectedAccountID: UUID?,
        startDate: Date? = nil) -> [ProviderPortfolioValueDTO] {
        guard selectedAccountID != nil else { return [] }
        let authorityDay = local
            .filter(\.isFresh)
            .map { HistoricalPriceCalendar.utcStartOfDay(for: $0.timestamp) }
            .min()
        let points = latestProviderByDay(provider).filter { point in
            authorityDay.map { point.day < $0 } ?? true
        }
        guard let startDate else { return points }
        return points.filter { $0.timestamp >= startDate }
    }

    private static func latestProviderByDay(
        _ points: [ProviderPortfolioValueDTO]) -> [ProviderPortfolioValueDTO] {
        var latest: [Date: ProviderPortfolioValueDTO] = [:]
        for point in points {
            if let existing = latest[point.day], existing.timestamp >= point.timestamp {
                continue
            }
            latest[point.day] = point
        }
        return latest.values.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.usdValue < $1.usdValue
        }
    }

    private static func filtered(
        _ points: [PortfolioHistoryPoint],
        startingAt startDate: Date?) -> [PortfolioHistoryPoint] {
        guard let startDate else { return points }
        return points.filter { $0.timestamp >= startDate }
    }

    private static func latestLocalByDay(
        _ observations: [LocalPortfolioValueObservation]) -> [LocalPortfolioValueObservation] {
        var latest: [Date: LocalPortfolioValueObservation] = [:]
        for observation in observations {
            let day = HistoricalPriceCalendar.utcStartOfDay(for: observation.timestamp)
            if let existing = latest[day], existing.timestamp >= observation.timestamp {
                continue
            }
            latest[day] = observation
        }
        return latest.values.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.usdValue < $1.usdValue
        }
    }
}
