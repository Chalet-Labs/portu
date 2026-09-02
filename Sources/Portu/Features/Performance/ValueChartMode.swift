import Charts
import PortuCore
import PortuUI
import SwiftUI

/// Passive renderer: the merged provider/local series, the estimated segment and
/// every disclosure flag arrive pre-shaped in `PerformanceValueChartData`, built
/// off the main actor by `PerformanceDataClient`. No SwiftData query, no merge,
/// no currency conversion happens during body evaluation.
struct ValueChartMode: View {
    let data: PerformanceValueChartData
    let historyStatus: PortfolioAnalyticsLoadStatus
    let currencyCode: String

    var body: some View {
        // The failure banner is derived purely from load status, so it is shared by the
        // empty state and the populated footer.
        let historyFailure = ProviderPortfolioHistory.refreshFailure(
            for: [],
            status: historyStatus)
        if data.points.isEmpty, data.estimatedPoints.isEmpty {
            Group {
                if let historyFailure {
                    ContentUnavailableView(
                        "Zerion history unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(historyFailure.message))
                } else if
                    data.hasRetainedProviderPoints,
                    data.hasConvertedProviderPoints == false {
                    ContentUnavailableView(
                        "Historical FX unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("No matching daily FX rates are available for Zerion history."))
                } else {
                    ContentUnavailableView(
                        "No Performance Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Sync your accounts to track portfolio performance"))
                }
            }
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
            .frame(height: 320)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(data.estimatedPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value))
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }

                    ForEach(data.points, id: \.date) { point in
                        if point.source == .local {
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value))
                                .foregroundStyle(
                                    .linearGradient(
                                        colors: [PortuTheme.dashboardGold.opacity(0.35), .clear],
                                        startPoint: .top, endPoint: .bottom))
                        }
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value))
                            .foregroundStyle(
                                point.source == .zerion
                                    ? PortuTheme.dashboardSecondaryText
                                    : PortuTheme.dashboardGold)
                            .lineStyle(
                                point.source == .zerion || point.isPartial
                                    ? StrokeStyle(lineWidth: 2, dash: [5, 3])
                                    : StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: currencyCode).precision(.fractionLength(0)))
                }
                .frame(height: 300)

                if let disclosure = data.providerDisclosure {
                    Label(
                        disclosure,
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
                if let failure = historyFailure {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
                if let conversionStart = data.historicalFXUnavailableBefore {
                    Label(
                        "Historical FX unavailable before \(conversionStart.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                } else if
                    data.hasRetainedProviderPoints,
                    data.hasConvertedProviderPoints == false {
                    Label(
                        "Historical FX unavailable for Zerion history",
                        systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
        }
    }
}
