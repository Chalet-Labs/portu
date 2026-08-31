import PortuCore
import PortuUI
import SwiftUI

/// Passive renderer: category changes and the top-five price changes arrive
/// pre-shaped, sorted and limited in `PerformanceBottomPanelData`, built off the
/// main actor by `PerformanceDataClient`. No SwiftData query, no dashboard
/// eligibility pass and no identity mapping happens during body evaluation.
struct PerformanceBottomPanel: View {
    let data: PerformanceBottomPanelData
    let currencyCode: String
    let historicalBackfillEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset categories")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                ForEach(data.categoryChanges) { change in
                    HStack {
                        Text(change.name).frame(width: 100, alignment: .leading)
                        Text(change.startValue, format: .currency(code: currencyCode)).frame(width: 100)
                        Text("\u{2192}").foregroundStyle(PortuTheme.dashboardSecondaryText)
                        Text(change.endValue, format: .currency(code: currencyCode)).frame(width: 100)
                        Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(change.percentChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                            .frame(width: 60)
                    }
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Asset prices")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                Text("Top assets with period price change")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                if historicalBackfillEnabled {
                    ForEach(data.priceChanges) { change in
                        HStack {
                            Text(change.name)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(2)
                                .truncationMode(.tail)
                            Text(change.endPrice, format: .currency(code: currencyCode))
                                .frame(width: 90, alignment: .trailing)
                            Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
                                .foregroundStyle(change.percentChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    }
                } else {
                    Text("Historical price backfill disabled")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
        }
        .frame(minHeight: 180, alignment: .topLeading)
    }
}
