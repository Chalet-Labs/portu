import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AssetPriceChart: View {
    let assetId: UUID
    let coinGeckoId: String?
    let store: StoreOf<AppFeature>

    @Query
    private var snapshots: [AssetSnapshot]
    @Query
    private var historicalPrices: [HistoricalPricePoint]

    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    init(assetId: UUID, coinGeckoId: String?, store: StoreOf<AppFeature>) {
        self.assetId = assetId
        self.coinGeckoId = coinGeckoId
        self.store = store
        let targetAssetId = assetId
        let targetCoinGeckoId = Self.normalizedCoinGeckoId(coinGeckoId) ?? "__missing_coin_gecko_id__"
        _snapshots = Query(
            filter: #Predicate<AssetSnapshot> { $0.assetId == targetAssetId },
            sort: \.timestamp)
        _historicalPrices = Query(
            filter: #Predicate<HistoricalPricePoint> { $0.coinGeckoId == targetCoinGeckoId },
            sort: \.day)
    }

    private var chartEntries: [SnapshotEntry] {
        let startDate = store.assetDetail.selectedRange.startDate
        return snapshots
            .filter { $0.timestamp >= startDate }
            .map { s in
                SnapshotEntry(
                    accountId: s.accountId,
                    assetId: s.assetId,
                    timestamp: s.timestamp,
                    grossUSD: s.usdValue,
                    borrowUSD: s.borrowUsdValue,
                    grossAmount: s.amount,
                    borrowAmount: s.borrowAmount)
            }
    }

    private var aggregated: [ChartDataPoint] {
        AssetDetailFeature.aggregateSnapshots(entries: chartEntries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Mode", selection: Binding(
                    get: { store.assetDetail.chartMode },
                    set: { store.send(.assetDetail(.chartModeChanged($0))) })) {
                        ForEach(ChartMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    .dashboardControl()

                Spacer()

                Picker("Range", selection: Binding(
                    get: { store.assetDetail.selectedRange },
                    set: { store.send(.assetDetail(.timeRangeChanged($0))) })) {
                        ForEach(ChartTimeRange.standard, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    .dashboardControl()
            }

            switch store.assetDetail.chartMode {
            case .price:
                priceChart
            case .dollarValue:
                valueChart
            case .amount:
                amountChart
            }
        }
    }

    // MARK: - Price chart (from CoinGecko historical API)

    private var priceChart: some View {
        Group {
            let points = if historicalBackfillEnabled {
                AssetDetailFeature.historicalPriceRows(
                    historicalPrices,
                    startDate: store.assetDetail.selectedRange.startDate,
                    isHistoricalBackfillEnabled: true)
            } else {
                [HistoricalPricePoint]()
            }
            if points.isEmpty {
                ContentUnavailableView(
                    "No Price History",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Run historical price cache from Settings"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 250)
            } else {
                Chart(points, id: \.id) { point in
                    LineMark(
                        x: .value("Date", point.day),
                        y: .value("Price", point.usdPrice))
                        .foregroundStyle(PortuTheme.dashboardGold)
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0 ... 4)))
                }
                .frame(height: 250)
            }
        }
    }

    // MARK: - $ Value chart (net from AssetSnapshot)

    private var valueChart: some View {
        Group {
            if aggregated.isEmpty {
                ContentUnavailableView(
                    "No Value Data", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see value history"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 250)
            } else {
                let isBorrowOnly = aggregated.allSatisfy { $0.grossUSD == 0 && $0.borrowUSD > 0 }

                Chart {
                    ForEach(aggregated) { point in
                        let net = point.grossUSD - point.borrowUSD
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", net))
                            .foregroundStyle(net < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardGold)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", net))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [
                                        (net < 0 ? Color.red : Color.accentColor).opacity(0.2),
                                        .clear
                                    ],
                                    startPoint: .top, endPoint: .bottom))
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 250)

                if isBorrowOnly {
                    Text("Debt history — this asset is only borrowed")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardGold)
                }
            }
        }
    }

    // MARK: - Amount chart (net from AssetSnapshot)

    private var amountChart: some View {
        Group {
            if aggregated.isEmpty {
                ContentUnavailableView(
                    "No Amount Data", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Sync your accounts to see amount history"))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(height: 250)
            } else {
                Chart {
                    ForEach(aggregated) { point in
                        let net = point.grossAmount - point.borrowAmount
                        LineMark(x: .value("Date", point.date), y: .value("Amount", net))
                            .foregroundStyle(net < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardGold)
                    }
                }
                .frame(height: 250)
            }
        }
    }

    private static func normalizedCoinGeckoId(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
