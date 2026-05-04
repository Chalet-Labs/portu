import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ExposureView: View {
    let store: StoreOf<AppFeature>

    @Query private var allTokens: [PositionToken]

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(allTokens)
    }

    private var byCategory: [CategoryExposure] {
        ExposureFeature.computeCategoryExposure(tokens: tokenEntries, prices: store.prices)
    }

    private var byAsset: [AssetExposure] {
        ExposureFeature.computeAssetExposure(tokens: tokenEntries, prices: store.prices)
    }

    private var summary: ExposureSummary {
        ExposureFeature.computeSummary(from: byCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                DashboardPageHeader("Portfolio Exposure")

                HStack(spacing: 12) {
                    summaryCard("Spot Total", value: summary.totalSpot)
                    summaryCard("Derivatives", value: 0, subtitle: "Coming soon")
                    summaryCard("Net Exposure", value: summary.netExposure, subtitle: "Excl. stablecoins")
                }

                Picker("View", selection: Binding(
                    get: { store.exposure.showByAsset },
                    set: { store.send(.exposure(.viewModeChanged($0))) })) {
                        Text("By Category").tag(false)
                        Text("By Asset").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    .dashboardControl()

                if store.exposure.showByAsset {
                    assetTable
                        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
                } else {
                    categoryTable
                        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
                }
            }
            .padding(DashboardStyle.pagePadding)
        }
        .dashboardPage()
    }

    // MARK: - Tables

    private var categoryTable: some View {
        Table(byCategory) {
            TableColumn("Category") { row in Text(row.name).fontWeight(.medium).foregroundStyle(PortuTheme.dashboardText) }
                .width(min: 100, ideal: 140)
            TableColumn("Spot Assets") { row in currencyCell(row.spotAssets) }
                .width(min: 80, ideal: 120)
            TableColumn("Liabilities") { row in liabilityCell(row.liabilities) }
                .width(min: 80, ideal: 120)
            TableColumn("Spot Net") { row in signedCell(row.spotNet) }
                .width(min: 80, ideal: 120)
            TableColumn("Derivatives") { _ in Text("\u{2014}").foregroundStyle(PortuTheme.dashboardTertiaryText) }
                .width(min: 60, ideal: 80)
            TableColumn("Net Exposure") { row in currencyCell(row.netExposure).fontWeight(.medium) }
                .width(min: 80, ideal: 120)
        }
        .dashboardTable()
    }

    private var assetTable: some View {
        Table(byAsset) {
            TableColumn("Asset") { row in Text(row.symbol).fontWeight(.medium).foregroundStyle(PortuTheme.dashboardText) }
                .width(min: 60, ideal: 80)
            TableColumn("Category") { row in
                Text(row.category.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Spot Assets") { row in currencyCell(row.spotAssets) }
            TableColumn("Liabilities") { row in liabilityCell(row.liabilities) }
            TableColumn("Spot Net") { row in signedCell(row.spotNet) }
            TableColumn("Net Exposure") { row in currencyCell(row.netExposure).fontWeight(.medium) }
        }
        .dashboardTable()
    }

    private func currencyCell(_ value: Decimal) -> Text {
        Text(value, format: .currency(code: "USD"))
            .font(DashboardStyle.monoTableFont)
    }

    private func liabilityCell(_ value: Decimal) -> some View {
        currencyCell(value).foregroundStyle(value > 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardSecondaryText)
    }

    private func signedCell(_ value: Decimal) -> some View {
        currencyCell(value).foregroundStyle(value < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardText)
    }

    // MARK: - Helpers

    private func summaryCard(_ title: String, value: Decimal, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DashboardStyle.labelFont)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
            Text(value, format: .currency(code: "USD"))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardText)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }
}
