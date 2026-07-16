import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

struct CurrencyConversionRateWriteResult: Equatable {
    var inserted: Int
    var updated: Int
}

struct CurrencyConversionRefreshResult: Equatable {
    let currency: FiatCurrency
    let currentUSDToDisplayRate: Decimal
    let insertedHistoricalRates: Int
    let updatedHistoricalRates: Int
}

struct HistoricalFXRefreshResult: Equatable {
    let currency: FiatCurrency
    let insertedHistoricalRates: Int
    let updatedHistoricalRates: Int
}

struct CurrencyConversionRefreshError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

enum CurrencyFXAvailability: Equatable {
    case available
    case loading
    case failed(String)
}

struct CurrencyConversionClient {
    var fetchCurrentUSDToDisplayRate: @MainActor @Sendable (FiatCurrency) async throws -> Decimal
    var refreshHistoricalRates: @MainActor @Sendable (FiatCurrency, Int) async throws -> HistoricalFXRefreshResult
    var refreshRates: @MainActor @Sendable (FiatCurrency, Int) async throws -> CurrencyConversionRefreshResult
}

extension CurrencyConversionClient: DependencyKey {
    static let liveValue = Self(
        fetchCurrentUSDToDisplayRate: { _ in
            fatalError("CurrencyConversionClient.liveValue must be overridden at Store creation")
        },
        refreshHistoricalRates: { _, _ in
            fatalError("CurrencyConversionClient.liveValue must be overridden at Store creation")
        },
        refreshRates: { _, _ in
            fatalError("CurrencyConversionClient.liveValue must be overridden at Store creation")
        })

    static let testValue = Self(
        fetchCurrentUSDToDisplayRate: { _ in 1 },
        refreshHistoricalRates: { currency, _ in
            HistoricalFXRefreshResult(
                currency: currency,
                insertedHistoricalRates: 0,
                updatedHistoricalRates: 0)
        },
        refreshRates: { currency, _ in
            CurrencyConversionRefreshResult(
                currency: currency,
                currentUSDToDisplayRate: 1,
                insertedHistoricalRates: 0,
                updatedHistoricalRates: 0)
        })
}

extension DependencyValues {
    var currencyConversion: CurrencyConversionClient {
        get { self[CurrencyConversionClient.self] }
        set { self[CurrencyConversionClient.self] = newValue }
    }
}

extension CurrencyConversionClient {
    @MainActor
    static func live(
        modelContext: ModelContext,
        priceService: PriceServiceClient,
        now: @escaping @Sendable () -> Date = { .now }) -> Self {
        let fetchCurrentUSDToDisplayRate: @MainActor @Sendable (FiatCurrency) async throws -> Decimal = { currency in
            guard currency != .usd else { return 1 }
            return try await priceService.fetchCurrentUSDConversionRate(currency)
        }
        let refreshHistoricalRates: @MainActor @Sendable (FiatCurrency, Int) async throws
            -> HistoricalFXRefreshResult = { currency, days in
                guard currency != .usd else {
                    return HistoricalFXRefreshResult(
                        currency: .usd,
                        insertedHistoricalRates: 0,
                        updatedHistoricalRates: 0)
                }

                let historicalRates = try await priceService.fetchHistoricalUSDConversionRates(currency, days)
                let write = try CurrencyConversionRateCacheWriter.upsert(
                    historicalRates,
                    in: modelContext,
                    fetchedAt: now())
                return HistoricalFXRefreshResult(
                    currency: currency,
                    insertedHistoricalRates: write.inserted,
                    updatedHistoricalRates: write.updated)
            }
        return Self(
            fetchCurrentUSDToDisplayRate: fetchCurrentUSDToDisplayRate,
            refreshHistoricalRates: refreshHistoricalRates,
            refreshRates: { currency, days in
                guard currency != .usd else {
                    return CurrencyConversionRefreshResult(
                        currency: .usd,
                        currentUSDToDisplayRate: 1,
                        insertedHistoricalRates: 0,
                        updatedHistoricalRates: 0)
                }

                let currentRate = try await fetchCurrentUSDToDisplayRate(currency)
                let historical = try await refreshHistoricalRates(currency, days)
                return CurrencyConversionRefreshResult(
                    currency: currency,
                    currentUSDToDisplayRate: currentRate,
                    insertedHistoricalRates: historical.insertedHistoricalRates,
                    updatedHistoricalRates: historical.updatedHistoricalRates)
            })
    }
}

enum CurrencyConversionRateCacheWriter {
    @MainActor
    static func upsert(
        _ rates: [CurrencyConversionRate],
        in context: ModelContext,
        fetchedAt: Date = .now) throws -> CurrencyConversionRateWriteResult {
        guard !rates.isEmpty else {
            return CurrencyConversionRateWriteResult(inserted: 0, updated: 0)
        }

        let incomingKeys = rates.map {
            CurrencyConversionRatePoint.cacheKey(baseCurrency: $0.base, quoteCurrency: $0.currency, day: $0.day)
        }
        let descriptor = FetchDescriptor<CurrencyConversionRatePoint>(
            predicate: #Predicate { incomingKeys.contains($0.cacheKey) })
        let existingRows = try context.fetch(descriptor)
        var existingByKey = Dictionary(
            grouping: existingRows,
            by: { CurrencyConversionRateCacheKey(
                baseCurrency: $0.baseCurrency,
                quoteCurrency: $0.quoteCurrency,
                day: $0.day) })

        do {
            var inserted = 0
            var updated = 0

            for rate in rates {
                let key = CurrencyConversionRateCacheKey(
                    baseCurrency: rate.base,
                    quoteCurrency: rate.currency,
                    day: rate.day)
                let matches = existingByKey[key, default: []]
                    .sorted { lhs, rhs in
                        if lhs.fetchedAt == rhs.fetchedAt {
                            return lhs.id.uuidString < rhs.id.uuidString
                        }
                        return lhs.fetchedAt > rhs.fetchedAt
                    }
                if let row = matches.first {
                    row.update(rate: rate.rate, fetchedAt: fetchedAt)
                    for duplicate in matches.dropFirst() {
                        context.delete(duplicate)
                    }
                    existingByKey[key] = [row]
                    updated += 1
                } else {
                    let row = CurrencyConversionRatePoint(rate, fetchedAt: fetchedAt)
                    context.insert(row)
                    existingByKey[key] = [row]
                    inserted += 1
                }
            }

            try context.save()
            return CurrencyConversionRateWriteResult(inserted: inserted, updated: updated)
        } catch {
            context.rollback()
            throw error
        }
    }
}

private struct CurrencyConversionRateCacheKey: Hashable {
    let baseCurrency: FiatCurrency
    let quoteCurrency: FiatCurrency
    let day: Date

    init(baseCurrency: FiatCurrency, quoteCurrency: FiatCurrency, day: Date) {
        self.baseCurrency = baseCurrency
        self.quoteCurrency = quoteCurrency
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
    }
}
