import SwiftUI
import SwiftData
import Charts
import PortuCore

struct AssetsChartMode: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp)
    private var snapshots: [AssetSnapshot]

    @State private var disabledCategories: Set<AssetCategory> = []

    private var filtered: [AssetSnapshot] {
        snapshots.filter { snap in
            snap.timestamp >= startDate &&
            !disabledCategories.contains(snap.category) &&
            (accountId == nil || snap.accountId == accountId)
        }
    }

    /// Group by timestamp + category, sum usdValue
    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let value: Decimal
    }

    private var chartData: [ChartPoint] {
        var grouped: [Date: [AssetCategory: Decimal]] = [:]
        for snap in filtered {
            // Bucket by day for cleaner charting
            let day = Calendar.current.startOfDay(for: snap.timestamp)
            grouped[day, default: [:]][snap.category, default: 0] += snap.usdValue
        }
        return grouped.flatMap { (date, categories) in
            categories.map { ChartPoint(date: date, category: $0.key.rawValue.capitalized, value: $0.value) }
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 8) {
            if chartData.isEmpty {
                ContentUnavailableView("No Asset Data", systemImage: "chart.bar.xaxis",
                                       description: Text("Sync to see asset category breakdown"))
                    .frame(height: 300)
            } else {
                Chart(chartData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Category", point.category))
                }
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .frame(height: 300)
                .padding()
            }

            // Category toggle chips
            HStack(spacing: 8) {
                ForEach(AssetCategory.allCases, id: \.self) { cat in
                    Button {
                        if disabledCategories.contains(cat) {
                            disabledCategories.remove(cat)
                        } else {
                            disabledCategories.insert(cat)
                        }
                    } label: {
                        Text(cat.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(disabledCategories.contains(cat) ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor.opacity(0.2)))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
