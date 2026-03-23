import Foundation
import PortuUI

enum PerformanceRange: String, CaseIterable, Identifiable, Sendable {
    case oneWeek = "1w"
    case oneMonth = "1m"
    case threeMonths = "3m"
    case oneYear = "1y"
    case yearToDate = "YTD"

    var id: String { rawValue }
    var title: String { rawValue }

    var pickerRange: TimeRangePicker.Range {
        switch self {
        case .oneWeek:
            .oneWeek
        case .oneMonth:
            .oneMonth
        case .threeMonths:
            .threeMonths
        case .oneYear:
            .oneYear
        case .yearToDate:
            .yearToDate
        }
    }

    func contains(
        _ date: Date,
        relativeTo referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        date >= lowerBound(relativeTo: referenceDate, calendar: calendar)
    }

    private func lowerBound(
        relativeTo referenceDate: Date,
        calendar: Calendar
    ) -> Date {
        switch self {
        case .oneWeek:
            calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        case .oneMonth:
            calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
        case .threeMonths:
            calendar.date(byAdding: .month, value: -3, to: referenceDate) ?? referenceDate
        case .oneYear:
            calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
        case .yearToDate:
            calendar.date(
                from: calendar.dateComponents([.year], from: referenceDate)
            ) ?? referenceDate
        }
    }
}
