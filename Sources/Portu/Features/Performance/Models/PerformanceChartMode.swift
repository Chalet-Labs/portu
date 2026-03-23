import Foundation

enum PerformanceChartMode: String, CaseIterable, Identifiable, Sendable {
    case value = "Value"
    case assets = "Assets"
    case pnl = "PnL"

    var id: String { rawValue }
    var title: String { rawValue }
}
