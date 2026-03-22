import Foundation
import Charts
import SwiftData
import SwiftUI
import PortuCore
import PortuUI

struct OverviewInspector: View {
    private struct InspectorSlice: Identifiable {
        let id: String
        let label: String
        let value: Decimal
        let share: Decimal
    }

    private struct WatchlistRow: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let price: Decimal
        let change24h: Decimal?
        let totalValue: Decimal
    }

    @Environment(AppState.self) private var appState
    @AppStorage("watchlistAssetCount") private var watchlistAssetCount = 5
    @Query private var positions: [Position]
    @State private var mode: OverviewInspectorMode = .byAsset

    private var viewModel: OverviewViewModel {
        OverviewViewModel(
            positions: positions,
            prices: appState.prices,
            changes24h: appState.priceChanges24h
        )
    }

    private var slices: [InspectorSlice] {
        switch mode {
        case .byAsset:
            return viewModel.topAssets.map { slice in
                InspectorSlice(
                    id: slice.id,
                    label: slice.label,
                    value: slice.value,
                    share: slice.shareOfPortfolio
                )
            }
        case .byCategory:
            return makeCategorySlices(from: viewModel.positions)
        }
    }

    private var watchlistRows: [WatchlistRow] {
        makeWatchlistRows(from: viewModel.positions)
            .prefix(watchlistAssetCount)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topAssetsSection
                watchlistSection
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, alignment: .topLeading)
    }

    private var topAssetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionHeader(
                    "Top Assets",
                    subtitle: "Portfolio concentration across your current holdings"
                )

                Spacer()

                Button("See all") {
                    appState.selectedSection = .allAssets
                }
                .buttonStyle(.plain)
            }

            Picker("Inspector Mode", selection: $mode) {
                ForEach(OverviewInspectorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if slices.isEmpty {
                Text("No portfolio allocation available yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Value", decimalValue(slice.value)),
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Label", slice.label))
                }
                .chartLegend(.hidden)
                .frame(height: 220)

                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(slices) { slice in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slice.label)
                                    .font(.subheadline.weight(.medium))
                                Text("\(slice.share.formatted(.number.precision(.fractionLength(1))))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            CurrencyText(slice.value)
                                .font(.subheadline.weight(.semibold))
                        }

                        if slice.id != slices.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                "Prices Watchlist",
                subtitle: "Top \(watchlistAssetCount) portfolio assets with live 24h changes"
            )

            if watchlistRows.isEmpty {
                Text("No watchlist assets available yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(watchlistRows) { row in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.symbol)
                                    .font(.headline)
                                Text(row.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text(row.price.formatted(.currency(code: "USD")))
                                    .font(.subheadline.weight(.semibold))
                                Text(changeLabel(for: row.change24h))
                                    .font(.caption)
                                    .foregroundStyle(changeColor(for: row.change24h))
                                CurrencyText(row.totalValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if row.id != watchlistRows.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func makeCategorySlices(from positions: [Position]) -> [InspectorSlice] {
        var totalsByCategory: [AssetCategory: Decimal] = [:]

        for position in positions {
            for token in position.tokens where token.role != .reward && token.role != .borrow {
                let category = token.asset?.category ?? .other
                let value = AssetValueFormatter.displayValue(
                    for: token,
                    livePrices: appState.prices
                )
                totalsByCategory[category, default: .zero] += value
            }
        }

        let totalValue = totalsByCategory.values.reduce(.zero, +)

        return totalsByCategory
            .map { category, value in
                InspectorSlice(
                    id: category.rawValue,
                    label: label(for: category),
                    value: value,
                    share: totalValue == .zero ? .zero : value / totalValue * 100
                )
            }
            .sorted { $0.value > $1.value }
    }

    private func makeWatchlistRows(from positions: [Position]) -> [WatchlistRow] {
        struct Accumulator {
            let id: String
            let symbol: String
            let name: String
            let coinGeckoId: String?
            var totalValue: Decimal
            var latestPrice: Decimal
        }

        var rowsByAsset: [String: Accumulator] = [:]

        for position in positions {
            for token in position.tokens where token.role != .reward && token.role != .borrow {
                let assetKey = makeAssetKey(for: token)
                let currentValue = AssetValueFormatter.displayValue(
                    for: token,
                    livePrices: appState.prices
                )
                let currentPrice = AssetValueFormatter.displayPrice(
                    for: token,
                    livePrices: appState.prices
                )

                if var existing = rowsByAsset[assetKey] {
                    existing.totalValue += currentValue
                    existing.latestPrice = currentPrice
                    rowsByAsset[assetKey] = existing
                } else {
                    rowsByAsset[assetKey] = Accumulator(
                        id: assetKey,
                        symbol: token.asset?.symbol ?? "Unknown",
                        name: token.asset?.name ?? token.asset?.symbol ?? "Unknown Asset",
                        coinGeckoId: token.asset?.coinGeckoId,
                        totalValue: currentValue,
                        latestPrice: currentPrice
                    )
                }
            }
        }

        return rowsByAsset.values
            .map { row in
                WatchlistRow(
                    id: row.id,
                    symbol: row.symbol,
                    name: row.name,
                    price: row.latestPrice,
                    change24h: row.coinGeckoId.flatMap { appState.priceChanges24h[$0] },
                    totalValue: row.totalValue
                )
            }
            .sorted { $0.totalValue > $1.totalValue }
    }

    private func label(for category: AssetCategory) -> String {
        switch category {
        case .major:
            return "Majors"
        case .stablecoin:
            return "Stablecoins"
        case .defi:
            return "DeFi"
        case .meme:
            return "Memecoins"
        case .privacy:
            return "Privacy"
        case .fiat:
            return "Fiat"
        case .governance:
            return "Governance"
        case .other:
            return "Other"
        }
    }

    private func changeLabel(for change24h: Decimal?) -> String {
        guard let change24h else {
            return "--"
        }

        let absoluteValue = change24h < .zero ? -change24h : change24h
        let prefix: String
        if change24h > .zero {
            prefix = "+"
        } else if change24h < .zero {
            prefix = "-"
        } else {
            prefix = ""
        }

        return "\(prefix)\(absoluteValue.formatted(.number.precision(.fractionLength(2))))%"
    }

    private func changeColor(for change24h: Decimal?) -> Color {
        guard let change24h else {
            return .secondary
        }

        return PortuTheme.changeColor(for: change24h)
    }

    private func decimalValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func makeAssetKey(for token: PositionToken) -> String {
        if let coinGeckoId = token.asset?.coinGeckoId {
            return "cg:\(coinGeckoId)"
        }
        if let assetID = token.asset?.id {
            return "asset:\(assetID.uuidString)"
        }
        return "token:\(token.id.uuidString)"
    }
}
