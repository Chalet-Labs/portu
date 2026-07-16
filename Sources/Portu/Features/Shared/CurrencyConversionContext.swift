import Foundation
import PortuCore

struct CurrencyConversionContext: Equatable {
    let displayCurrency: FiatCurrency
    let currentUSDToDisplayRate: Decimal
    let historicalUSDToDisplayRatesByDay: [Date: Decimal]

    static let usd = CurrencyConversionContext(
        displayCurrency: .usd,
        currentUSDToDisplayRate: 1,
        historicalUSDToDisplayRatesByDay: [:])

    init(
        displayCurrency: FiatCurrency = .default,
        currentUSDToDisplayRate: Decimal = 1,
        historicalUSDToDisplayRatesByDay: [Date: Decimal] = [:]) {
        self.displayCurrency = displayCurrency
        self.currentUSDToDisplayRate = currentUSDToDisplayRate
        // Sort by the original (pre-truncation) timestamp first so that when multiple
        // entries collapse onto the same UTC day, `uniquingKeysWith` deterministically
        // keeps the chronologically latest one — Dictionary iteration order alone is
        // not deterministic and would otherwise pick an arbitrary winner.
        self.historicalUSDToDisplayRatesByDay = Dictionary(
            historicalUSDToDisplayRatesByDay
                .sorted { $0.key < $1.key }
                .map { (HistoricalPriceCalendar.utcStartOfDay(for: $0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest })
    }

    init(
        displayCurrency: FiatCurrency,
        currentUSDToDisplayRate: Decimal,
        historicalRatePoints: [CurrencyConversionRatePoint]) {
        let rates = Dictionary(
            historicalRatePoints.compactMap { point -> (Date, Decimal)? in
                guard
                    point.baseCurrency == .usd,
                    point.quoteCurrency == displayCurrency
                else { return nil }
                return (point.day, point.rate)
            },
            uniquingKeysWith: { _, latest in latest })
        self.init(
            displayCurrency: displayCurrency,
            currentUSDToDisplayRate: currentUSDToDisplayRate,
            historicalUSDToDisplayRatesByDay: rates)
    }

    func rate(for date: Date, today: Date = .now) -> Decimal {
        guard displayCurrency != .usd else { return 1 }
        let day = HistoricalPriceCalendar.utcStartOfDay(for: date)
        // The historical-FX top-up fetches today's row at most once per day (see
        // AppFeature.historicalFXTopUpEffect), so it goes stale as currentUSDToDisplayRate
        // keeps refreshing every periodic tick. Always prefer the live spot rate for
        // today's UTC day rather than the cached historical row.
        guard day != HistoricalPriceCalendar.utcStartOfDay(for: today) else { return currentUSDToDisplayRate }
        return historicalUSDToDisplayRatesByDay[day] ?? currentUSDToDisplayRate
    }

    func convertUSDValue(_ value: Decimal, on date: Date, today: Date = .now) -> Decimal {
        value * rate(for: date, today: today)
    }

    func convertUSDPoint(_ point: HistoricalPortfolioValuePoint, today: Date = .now) -> HistoricalPortfolioValuePoint {
        HistoricalPortfolioValuePoint(
            date: point.date,
            value: convertUSDValue(point.value, on: point.date, today: today),
            kind: point.kind)
    }
}
