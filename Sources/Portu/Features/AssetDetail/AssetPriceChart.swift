import SwiftUI
import SwiftData
import Charts
import PortuCore

struct AssetPriceChart: View {
    let assetId: UUID
    let coinGeckoId: String?

    @Query(sort: \AssetSnapshot.timestamp)
    private var snapshots: [AssetSnapshot]

    @State private var chartMode: ChartMode = .price
    @State private var selectedRange: TimeRange = .oneMonth

    enum ChartMode: String, CaseIterable {
        case price = "Price"
        case dollarValue = "$ Value"
        case amount = "Amount"
    }

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W", oneMonth = "1M", threeMonths = "3M", oneYear = "1Y"

        var startDate: Date {
            let cal = Calendar.current
            let now = Date.now
            return switch self {
            case .oneWeek: cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            case .oneMonth: cal.date(byAdding: .month, value: -1, to: now)!
            case .threeMonths: cal.date(byAdding: .month, value: -3, to: now)!
            case .oneYear: cal.date(byAdding: .year, value: -1, to: now)!
            }
        }
    }

    private var assetSnapshots: [AssetSnapshot] {
        snapshots.filter { $0.assetId == assetId && $0.timestamp >= selectedRange.startDate }
    }

    /// Aggregate by timestamp (sum across accounts)
    private var aggregated: [(Date, Decimal, Decimal, Decimal, Decimal)] {
        // (date, grossUSD, borrowUSD, grossAmount, borrowAmount)
        var byDate: [Date: (Decimal, Decimal, Decimal, Decimal)] = [:]
        for s in assetSnapshots {
            let day = Calendar.current.startOfDay(for: s.timestamp)
            var entry = byDate[day] ?? (0, 0, 0, 0)
            entry.0 += s.usdValue
            entry.1 += s.borrowUsdValue
            entry.2 += s.amount
            entry.3 += s.borrowAmount
            byDate[day] = entry
        }
        return byDate.sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.0, $0.value.1, $0.value.2, $0.value.3) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Mode", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Spacer()

                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            switch chartMode {
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
            if coinGeckoId != nil {
                // TODO: Fetch historical prices from CoinGecko /coins/{id}/market_chart
                ContentUnavailableView("Price History", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Historical price chart — requires CoinGecko market_chart API integration"))
                    .frame(height: 250)
            } else {
                ContentUnavailableView("No Price Data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Asset has no CoinGecko ID for price history"))
                    .frame(height: 250)
            }
        }
    }

    // MARK: - $ Value chart (net from AssetSnapshot)

    private var valueChart: some View {
        Group {
            if aggregated.isEmpty {
                ContentUnavailableView("No Value Data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Sync your accounts to see value history"))
                    .frame(height: 250)
            } else {
                let isBorrowOnly = aggregated.allSatisfy { $0.1 == 0 && $0.2 > 0 }

                Chart {
                    ForEach(aggregated, id: \.0) { (date, gross, borrow, _, _) in
                        let net = gross - borrow
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Value", net)
                        )
                        .foregroundStyle(net < 0 ? .red : Color.accentColor)

                        AreaMark(
                            x: .value("Date", date),
                            y: .value("Value", net)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [
                                    (net < 0 ? Color.red : Color.accentColor).opacity(0.2),
                                    .clear
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 250)

                if isBorrowOnly {
                    Text("Debt history — this asset is only borrowed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Amount chart (net from AssetSnapshot)

    private var amountChart: some View {
        Group {
            if aggregated.isEmpty {
                ContentUnavailableView("No Amount Data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Sync your accounts to see amount history"))
                    .frame(height: 250)
            } else {
                Chart {
                    ForEach(aggregated, id: \.0) { (date, _, _, grossAmt, borrowAmt) in
                        let net = grossAmt - borrowAmt
                        LineMark(x: .value("Date", date), y: .value("Amount", net))
                            .foregroundStyle(net < 0 ? .red : Color.accentColor)
                    }
                }
                .frame(height: 250)
            }
        }
    }
}
