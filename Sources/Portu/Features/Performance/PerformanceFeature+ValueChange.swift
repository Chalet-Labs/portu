import Foundation

struct ValueChangeObservation: Equatable {
    let date: Date
    let value: Decimal
    let isReliable: Bool
}

/// Consecutive observed portfolio-value change. This is not cost-basis P&L.
struct ValueChangeBar: Identifiable, Equatable {
    let id: Date
    let date: Date
    let change: Decimal
    let cumulative: Decimal
}

struct ValueChangeSeries: Equatable {
    let bars: [ValueChangeBar]
    let hasSkippedTransitions: Bool
}

extension PerformanceFeature {
    static func lastValueChangeObservationPerDay(
        _ observations: [ValueChangeObservation]) -> [ValueChangeObservation] {
        var latestByDay: [Date: ValueChangeObservation] = [:]
        for observation in observations {
            let day = utcStartOfDay(for: observation.date)
            if let existing = latestByDay[day], existing.date >= observation.date {
                continue
            }
            latestByDay[day] = observation
        }
        return latestByDay.values.sorted { $0.date < $1.date }
    }

    /// Compute consecutive observed value changes with cumulative totals.
    static func computeValueChangeSeries(
        from observations: [ValueChangeObservation]) -> ValueChangeSeries {
        guard observations.count >= 2 else {
            return ValueChangeSeries(bars: [], hasSkippedTransitions: false)
        }
        var result: [ValueChangeBar] = []
        var cumulative: Decimal = 0
        var hasSkippedTransitions = false
        for index in 1 ..< observations.count {
            let previous = observations[index - 1]
            let current = observations[index]
            guard previous.isReliable, current.isReliable else {
                hasSkippedTransitions = true
                continue
            }
            let change = current.value - previous.value
            cumulative += change
            result.append(ValueChangeBar(
                id: current.date,
                date: current.date,
                change: change,
                cumulative: cumulative))
        }
        return ValueChangeSeries(
            bars: result,
            hasSkippedTransitions: hasSkippedTransitions)
    }

    static func computeValueChangeBars(
        from observations: [ValueChangeObservation]) -> [ValueChangeBar] {
        computeValueChangeSeries(from: observations).bars
    }

    static func computeValueChangeBars(
        from dailyValues: [(Date, Decimal)]) -> [ValueChangeBar] {
        computeValueChangeBars(from: dailyValues.map {
            ValueChangeObservation(date: $0.0, value: $0.1, isReliable: true)
        })
    }

    static func computeValueChangeBars(
        from observations: [ValueChangeObservation],
        conversionContext: CurrencyConversionContext) -> [ValueChangeBar] {
        computeValueChangeSeries(
            from: observations,
            conversionContext: conversionContext).bars
    }

    static func computeValueChangeSeries(
        from observations: [ValueChangeObservation],
        conversionContext: CurrencyConversionContext) -> ValueChangeSeries {
        let converted = observations.map { observation in
            ValueChangeObservation(
                date: observation.date,
                value: conversionContext.convertUSDValue(observation.value, on: observation.date),
                isReliable: observation.isReliable)
        }
        return computeValueChangeSeries(from: converted)
    }

    static func computeValueChangeBars(
        from dailyValues: [(Date, Decimal)],
        conversionContext: CurrencyConversionContext) -> [ValueChangeBar] {
        computeValueChangeBars(
            from: dailyValues.map {
                ValueChangeObservation(date: $0.0, value: $0.1, isReliable: true)
            },
            conversionContext: conversionContext)
    }
}
