import Foundation

struct PnLBarPoint: Identifiable, Sendable {
    let id: Date
    let date: Date
    let value: Decimal
    let cumulativeValue: Decimal

    init(
        date: Date,
        value: Decimal,
        cumulativeValue: Decimal
    ) {
        self.id = date
        self.date = date
        self.value = value
        self.cumulativeValue = cumulativeValue
    }
}
