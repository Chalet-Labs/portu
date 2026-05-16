import ComposableArchitecture
import Foundation
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ExposureView: View {
    let store: StoreOf<AppFeature>

    @Environment(AppState.self) private var appState
    @Environment(\.historicalPricesUSD) private var historicalPricesUSD
    @Query private var allTokens: [PositionToken]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @Query private var tokenIdentityMappings: [TokenIdentityMapping]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    private var tokenEntries: [TokenEntry] {
        TokenEntry.fromActiveTokens(
            allTokens,
            categoryResolver: PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules))
    }

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init)
    }

    private var mappingSnapshots: [TokenIdentityMappingSnapshot] {
        tokenIdentityMappings.map(TokenIdentityMappingSnapshot.init)
    }

    private var mappedTokenEntries: [TokenEntry] {
        TokenSettingsFeature.applyIdentityMappings(
            to: tokenEntries,
            mappings: mappingSnapshots,
            overrides: overrideSnapshots)
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    var body: some View {
        let data = ExposureFeature.computeDashboardData(
            tokens: mappedTokenEntries,
            prices: displayPrices,
            overrides: overrideSnapshots,
            settings: dashboardSettings)

        return GeometryReader { proxy in
            let isCompact = proxy.size.width < ExposureLayout.compactWidth

            ScrollView {
                VStack(alignment: .leading, spacing: ExposureLayout.sectionSpacing) {
                    pageHeader

                    ExposureSummaryGrid(summary: data.summary, isCompact: isCompact)

                    ExposureCategoryTable(rows: data.categoryRows)

                    ExposureAssetTable(rows: data.assetRows)
                }
                .padding(DashboardStyle.pagePadding)
            }
            .background(PortuTheme.dashboardBackground)
        }
        .dashboardPage()
        .task(id: data.pollingIDs) {
            if data.pollingIDs.isEmpty {
                store.send(.stopPricePolling)
            } else {
                store.send(.startPricePolling(data.pollingIDs))
            }
        }
        .onDisappear {
            store.send(.stopPricePolling)
        }
    }

    private var pageHeader: some View {
        DashboardPageHeader("Portfolio Exposure") {
            DashboardHeaderSyncActions(
                lastPriceUpdate: store.lastPriceUpdate,
                isSyncing: appState.syncStatus.isSyncing) {
                    appState.onSyncRequested?()
                }
        }
    }

    private var displayPrices: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: store.prices,
            historical: historicalPricesUSD)
    }
}

private enum ExposureLayout {
    static let compactWidth: CGFloat = 980
    static let sectionSpacing: CGFloat = 32
    static let cardSpacing: CGFloat = 12
    static let tableSpacing: CGFloat = 14
    static let tableRowHeight: CGFloat = 30
    static let tableHeaderHeight: CGFloat = 34
    static let tableCornerRadius: CGFloat = 6
    static let tableHorizontalPadding: CGFloat = 12
    static let categoryColumnWidth: CGFloat = 190
    static let exposurePairColumnWidth: CGFloat = 260
    static let spotNetColumnWidth: CGFloat = 160
    static let derivativesColumnWidth: CGFloat = 230
    static let netExposureColumnWidth: CGFloat = 210
    static let columnSpacing: CGFloat = 12

    static var tableWidth: CGFloat {
        categoryColumnWidth + exposurePairColumnWidth + spotNetColumnWidth
            + derivativesColumnWidth + netExposureColumnWidth
            + columnSpacing * 4 + tableHorizontalPadding * 2
    }
}

private struct ExposureSummaryGrid: View {
    let summary: ExposureSummary
    let isCompact: Bool

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: ExposureLayout.cardSpacing),
            count: isCompact ? 2 : 4)
    }

    private var netExposureShare: Decimal {
        guard summary.totalSpot > 0 else { return 0 }
        return summary.netExposure / summary.totalSpot
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: ExposureLayout.cardSpacing) {
            ExposureSummaryCard(title: "Spot total") {
                Text(ExposureFormat.currency(summary.totalSpot, fractionDigits: 2))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            ExposureSummaryCard(title: "Derivatives") {
                VStack(alignment: .leading, spacing: 7) {
                    ExposureDerivativeSummaryLine(label: "Long", color: PortuTheme.dashboardSuccess)
                    ExposureDerivativeSummaryLine(label: "Short", color: PortuTheme.dashboardWarning)
                }
            }

            ExposureSummaryCard(title: "Derivatives total") {
                Text(ExposureFormat.placeholder)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                Text("Not yet available")
                    .font(.caption2)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }

            ExposureSummaryCard(title: "Net exposure (excl. stablecoins)") {
                Text(ExposureFormat.currency(summary.netExposure, fractionDigits: 2))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("\(ExposureFormat.percent(netExposureShare, fractionDigits: 2)) of spot total")
                    .font(.caption2)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            }
        }
    }
}

private struct ExposureSummaryCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            content

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .dashboardCard(horizontalPadding: 14, verticalPadding: 12)
    }
}

private struct ExposureDerivativeSummaryLine: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(ExposureFormat.placeholder)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 42, alignment: .leading)
            Text(label)
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        }
    }
}

private struct ExposureCategoryTable: View {
    let rows: [CategoryExposure]

    var body: some View {
        ExposureTableSection(title: "Exposure by asset category") {
            ExposureTableHeader(firstColumnTitle: "Category")

            ExposureTableRows(rows: rows, emptyTitle: "No category exposure") { row, index in
                ExposureCategoryRow(row: row, index: index)
            }
        }
    }
}

private struct ExposureAssetTable: View {
    let rows: [AssetExposure]

    var body: some View {
        ExposureTableSection(title: "Exposure by asset") {
            ExposureTableHeader(firstColumnTitle: "Asset")

            ExposureTableRows(rows: rows, emptyTitle: "No asset exposure") { row, index in
                ExposureAssetRow(row: row, index: index)
            }
        } trailing: {
            ExposureCountPill(title: ExposureLabels.assetCountPillTitle, count: rows.count)
        }
    }
}

private struct ExposureTableSection<Content: View, Trailing: View>: View {
    let title: String
    let content: Content
    let trailing: Trailing

    init(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExposureLayout.tableSpacing) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PortuTheme.dashboardText)

                Spacer(minLength: 12)

                trailing
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    content
                }
                .frame(width: ExposureLayout.tableWidth, alignment: .leading)
            }
            .dashboardTable()
            .clipShape(RoundedRectangle(cornerRadius: ExposureLayout.tableCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ExposureLayout.tableCornerRadius, style: .continuous)
                    .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
        }
    }
}

private struct ExposureTableHeader: View {
    let firstColumnTitle: String

    var body: some View {
        HStack(spacing: ExposureLayout.columnSpacing) {
            ExposureHeaderText(firstColumnTitle, width: ExposureLayout.categoryColumnWidth, alignment: .leading)
            ExposureHeaderText(
                "Spot Assets / Liabilities",
                width: ExposureLayout.exposurePairColumnWidth,
                alignment: .trailing)
            ExposureSortHeader("Spot Net", width: ExposureLayout.spotNetColumnWidth)
            ExposureHeaderText(
                "Derivatives Long / Short",
                width: ExposureLayout.derivativesColumnWidth,
                alignment: .center)
            ExposureSortHeader("Net Exposure", width: ExposureLayout.netExposureColumnWidth)
        }
        .padding(.horizontal, ExposureLayout.tableHorizontalPadding)
        .frame(height: ExposureLayout.tableHeaderHeight)
        .background(PortuTheme.dashboardBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)
        }
    }
}

private struct ExposureTableRows<Row: ExposureRow, RowView: View>: View {
    let rows: [Row]
    let emptyTitle: String
    let rowView: (Row, Int) -> RowView

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "chart.bar.xaxis",
                description: Text("Synced balances will appear here."))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, index)
                }
            }
        }
    }
}

private struct ExposureCategoryRow: View {
    let row: CategoryExposure
    let index: Int

    var body: some View {
        ExposureTableRow(index: index) {
            Text(row.name)
                .fontWeight(.medium)
                .foregroundStyle(PortuTheme.dashboardText)
                .frame(width: ExposureLayout.categoryColumnWidth, alignment: .leading)

            ExposureSpotLiabilityCell(row: row)
                .frame(width: ExposureLayout.exposurePairColumnWidth, alignment: .trailing)

            ExposureCurrencyCell(value: row.netExposure, fractionDigits: 0)
                .frame(width: ExposureLayout.spotNetColumnWidth, alignment: .trailing)

            ExposureDerivativesCell()
                .frame(width: ExposureLayout.derivativesColumnWidth, alignment: .center)

            ExposureNetExposureCell(row: row)
                .frame(width: ExposureLayout.netExposureColumnWidth, alignment: .trailing)
        }
    }
}

private struct ExposureAssetRow: View {
    let row: AssetExposure
    let index: Int

    var body: some View {
        ExposureTableRow(index: index) {
            ExposureAssetBadge(symbol: row.symbol, logoURL: row.logoURL)
                .frame(width: ExposureLayout.categoryColumnWidth, alignment: .leading)

            ExposureSpotLiabilityCell(row: row)
                .frame(width: ExposureLayout.exposurePairColumnWidth, alignment: .trailing)

            ExposureCurrencyCell(value: row.netExposure, fractionDigits: 0)
                .frame(width: ExposureLayout.spotNetColumnWidth, alignment: .trailing)

            ExposureDerivativesCell()
                .frame(width: ExposureLayout.derivativesColumnWidth, alignment: .center)

            ExposureNetExposureCell(row: row)
                .frame(width: ExposureLayout.netExposureColumnWidth, alignment: .trailing)
        }
    }
}

private struct ExposureTableRow<Content: View>: View {
    let index: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: ExposureLayout.columnSpacing) {
            content
        }
        .padding(.horizontal, ExposureLayout.tableHorizontalPadding)
        .frame(height: ExposureLayout.tableRowHeight)
        .background(index.isMultiple(of: 2) ? Color.clear : PortuTheme.dashboardPanelElevatedBackground.opacity(0.24))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PortuTheme.dashboardStroke.opacity(0.72))
                .frame(height: 1)
        }
    }
}

private struct ExposureHeaderText: View {
    let title: String
    let width: CGFloat
    let alignment: Alignment

    init(_ title: String, width: CGFloat, alignment: Alignment) {
        self.title = title
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

private struct ExposureSortHeader: View {
    let title: String
    let width: CGFloat

    init(_ title: String, width: CGFloat) {
        self.title = title
        self.width = width
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(PortuTheme.dashboardText)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PortuTheme.dashboardMutedPanelBackground))
        .frame(width: width, alignment: .trailing)
    }
}
