import SwiftUI
import SwiftData
import PortuCore

struct PerformanceBottomPanel: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp) private var snapshots: [AssetSnapshot]

    /// Category breakdown: compare start vs end usdValue per category
    private var categoryChanges: [(String, Decimal, Decimal, Decimal)] {
        let filtered = snapshots.filter { s in
            s.timestamp >= startDate && (accountId == nil || s.accountId == accountId)
        }
        guard !filtered.isEmpty else { return [] }

        let sorted = filtered.sorted { $0.timestamp < $1.timestamp }
        let firstDay = Calendar.current.startOfDay(for: sorted.first!.timestamp)
        let lastDay = Calendar.current.startOfDay(for: sorted.last!.timestamp)

        var startValues: [AssetCategory: Decimal] = [:]
        var endValues: [AssetCategory: Decimal] = [:]

        for s in sorted {
            let day = Calendar.current.startOfDay(for: s.timestamp)
            if day == firstDay { startValues[s.category, default: 0] += s.usdValue }
            if day == lastDay { endValues[s.category, default: 0] += s.usdValue }
        }

        return AssetCategory.allCases.compactMap { cat in
            let start = startValues[cat, default: 0]
            let end = endValues[cat, default: 0]
            guard start > 0 || end > 0 else { return nil }
            let change = start > 0 ? (end - start) / start : 0
            return (cat.rawValue.capitalized, start, end, change)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Asset categories panel
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Categories").font(.headline)
                ForEach(categoryChanges, id: \.0) { (name, start, end, change) in
                    HStack {
                        Text(name).frame(width: 100, alignment: .leading)
                        Text(start, format: .currency(code: "USD")).frame(width: 100)
                        Text("\u{2192}").foregroundStyle(.secondary)
                        Text(end, format: .currency(code: "USD")).frame(width: 100)
                        Text(change, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(change >= 0 ? .green : .red)
                            .frame(width: 60)
                    }
                    .font(.caption)
                }
            }

            Divider()

            // Asset prices panel
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Prices").font(.headline)
                Text("Top assets with period price change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // TODO: Populate from PriceService historical data
            }
        }
        .padding()
        .frame(height: 200)
    }
}
