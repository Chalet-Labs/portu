import Charts
import SwiftUI
import PortuUI

struct AssetPriceChart: View {
    @Binding private var mode: AssetChartMode
    @Binding private var selectedComparison: AssetComparison?

    let priceSeries: [PerformancePoint]
    let valueSeries: [PerformancePoint]
    let amountSeries: [PerformancePoint]
    let comparisonSeries: [PerformancePoint]

    @State private var selectedRange: TimeRangePicker.Range = .oneMonth

    init(
        mode: Binding<AssetChartMode>,
        selectedComparison: Binding<AssetComparison?> = .constant(nil),
        priceSeries: [PerformancePoint],
        valueSeries: [PerformancePoint],
        amountSeries: [PerformancePoint],
        comparisonSeries: [PerformancePoint] = []
    ) {
        _mode = mode
        _selectedComparison = selectedComparison
        self.priceSeries = priceSeries
        self.valueSeries = valueSeries
        self.amountSeries = amountSeries
        self.comparisonSeries = comparisonSeries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls

            if filteredDisplayedSeries.isEmpty {
                emptyState(emptyStateMessage)
            } else if showsComparisonOverlay {
                normalizedComparisonChart
            } else {
                standardChart
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                SectionHeader(
                    sectionTitle,
                    subtitle: sectionSubtitle
                )

                Spacer()

                Picker("Mode", selection: $mode) {
                    ForEach(AssetChartMode.allCases) { chartMode in
                        Text(chartMode.title).tag(chartMode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            HStack(alignment: .center, spacing: 16) {
                TimeRangePicker(selection: $selectedRange)
                    .frame(maxWidth: 320)

                if mode == .price {
                    comparisonControls
                }
            }
        }
    }

    private var comparisonControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                comparisonChip(
                    title: "No Comparison",
                    comparison: nil
                )

                ForEach(AssetComparison.allCases) { comparison in
                    comparisonChip(
                        title: comparison.symbol,
                        comparison: comparison
                    )
                }
            }
        }
    }

    private var standardChart: some View {
        Chart {
            if displaysZeroRule {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.quaternary)
            }

            ForEach(filteredDisplayedSeries) { point in
                LineMark(
                    x: .value("Timestamp", point.date),
                    y: .value(yAxisTitle, doubleValue(point.value))
                )
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(height: 260)
    }

    private var normalizedComparisonChart: some View {
        Chart {
            ForEach(normalizedPrimarySeries) { point in
                LineMark(
                    x: .value("Timestamp", point.date),
                    y: .value("Normalized", point.value)
                )
                .foregroundStyle(by: .value("Series", "Asset"))
            }

            ForEach(normalizedComparisonSeries) { point in
                LineMark(
                    x: .value("Timestamp", point.date),
                    y: .value("Normalized", point.value)
                )
                .foregroundStyle(by: .value("Series", comparisonLegendTitle))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .chartLegend(position: .bottom)
        .chartForegroundStyleScale([
            "Asset": Color.accentColor,
            comparisonLegendTitle: Color.secondary
        ])
        .frame(height: 260)
    }

    private var sectionTitle: String {
        switch mode {
        case .price:
            "Asset Price"
        case .value:
            "Net Value"
        case .amount:
            "Net Amount"
        }
    }

    private var sectionSubtitle: String {
        switch mode {
        case .price:
            if selectedComparison != nil && showsComparisonOverlay {
                return "CoinGecko market history with normalized comparison overlay"
            }

            return "CoinGecko historical market price over the selected range"
        case .value:
            return "Net holdings value from asset snapshots across all active accounts"
        case .amount:
            return "Net token quantity from asset snapshots across all active accounts"
        }
    }

    private var displayedSeries: [PerformancePoint] {
        switch mode {
        case .price:
            priceSeries
        case .value:
            valueSeries
        case .amount:
            amountSeries
        }
    }

    private var filteredDisplayedSeries: [PerformancePoint] {
        displayedSeries.filter { $0.date >= cutoffDate }
    }

    private var filteredComparisonSeries: [PerformancePoint] {
        comparisonSeries.filter { $0.date >= cutoffDate }
    }

    private var showsComparisonOverlay: Bool {
        mode == .price
            && selectedComparison != nil
            && normalizedPrimarySeries.isEmpty == false
            && normalizedComparisonSeries.isEmpty == false
    }

    private var normalizedPrimarySeries: [NormalizedChartPoint] {
        normalizedSeries(from: filteredDisplayedSeries)
    }

    private var normalizedComparisonSeries: [NormalizedChartPoint] {
        normalizedSeries(from: filteredComparisonSeries)
    }

    private var comparisonLegendTitle: String {
        selectedComparison?.symbol ?? "Comparison"
    }

    private var displaysZeroRule: Bool {
        filteredDisplayedSeries.contains { $0.value < .zero }
    }

    private var yAxisTitle: String {
        switch mode {
        case .price:
            "Price"
        case .value:
            "Value"
        case .amount:
            "Amount"
        }
    }

    private var emptyStateMessage: String {
        switch mode {
        case .price:
            "Price history is unavailable until CoinGecko market data is loaded."
        case .value:
            "Sync asset snapshots to chart net value over time."
        case .amount:
            "Sync asset snapshots to chart net amount over time."
        }
    }

    private var cutoffDate: Date {
        let calendar = Calendar.current
        let now = Date.now

        switch selectedRange {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .yearToDate:
            return calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        }
    }

    private func comparisonChip(
        title: String,
        comparison: AssetComparison?
    ) -> some View {
        let isSelected = selectedComparison == comparison

        return Button {
            selectedComparison = comparison
        } label: {
            Text(title)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(isSelected ? Color.white : .primary)
        .background(
            isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
    }

    private func normalizedSeries(
        from series: [PerformancePoint]
    ) -> [NormalizedChartPoint] {
        Self.normalizedOverlaySeries(from: series).map { point in
            NormalizedChartPoint(
                date: point.date,
                value: doubleValue(point.value)
            )
        }
    }

    static func normalizedOverlaySeries(
        from series: [PerformancePoint]
    ) -> [PerformancePoint] {
        guard let baseline = series.first?.value,
              baseline != .zero
        else {
            return []
        }

        return series.map { point in
            PerformancePoint(
                date: point.date,
                value: point.value / baseline * 100,
                usesAccountSnapshot: false
            )
        }
    }

    private func emptyState(
        _ message: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary.opacity(0.6))
            .frame(height: 260)
            .overlay {
                Text(message)
                    .foregroundStyle(.secondary)
            }
    }

    private func doubleValue(
        _ value: Decimal
    ) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private struct NormalizedChartPoint: Identifiable {
    let id: Date
    let date: Date
    let value: Double

    init(
        date: Date,
        value: Double
    ) {
        id = date
        self.date = date
        self.value = value
    }
}
