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
        self.historicalUSDToDisplayRatesByDay = Dictionary(uniqueKeysWithValues: historicalUSDToDisplayRatesByDay.map {
            (HistoricalPriceCalendar.utcStartOfDay(for: $0.key), $0.value)
        })
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

    func rate(for date: Date) -> Decimal {
        guard displayCurrency != .usd else { return 1 }
        let day = HistoricalPriceCalendar.utcStartOfDay(for: date)
        return historicalUSDToDisplayRatesByDay[day] ?? currentUSDToDisplayRate
    }

    func convertUSDValue(_ value: Decimal, on date: Date) -> Decimal {
        value * rate(for: date)
    }

    func convertUSDPoint(_ point: HistoricalPortfolioValuePoint) -> HistoricalPortfolioValuePoint {
        HistoricalPortfolioValuePoint(
            date: point.date,
            value: convertUSDValue(point.value, on: point.date),
            kind: point.kind)
    }
}
