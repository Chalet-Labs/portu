import Foundation

public enum ChartTimeRange: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case ytd = "YTD"
    case custom = "Custom"

    public var startDate: Date {
        startDate(at: .now)
    }

    public func startDate(at date: Date) -> Date {
        let cal = Calendar.current
        return switch self {
        case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: date)!
        case .oneMonth: cal.date(byAdding: .month, value: -1, to: date)!
        case .threeMonths: cal.date(byAdding: .month, value: -3, to: date)!
        case .oneYear: cal.date(byAdding: .year, value: -1, to: date)!
        case .ytd: cal.date(from: cal.dateComponents([.year], from: date))!
        case .custom: cal.date(byAdding: .month, value: -1, to: date)!
        }
    }

    /// The four standard ranges shared by views that don't need ytd/custom.
    public static let standard: [ChartTimeRange] = [.oneWeek, .oneMonth, .threeMonths, .oneYear]
}
