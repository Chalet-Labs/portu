import PortuCore
import SwiftData
import SwiftUI

struct PerformanceBottomPanel: View {
    let accountId: UUID?
    let startDate: Date

    @Query(sort: \AssetSnapshot.timestamp) private var snapshots: [AssetSnapshot]

    private var categoryChanges: [CategoryChange] {
        let entries = snapshots
            .filter { s in
                s.timestamp >= startDate && (accountId == nil || s.accountId == accountId)
            }
            .map {
                CategorySnapshotEntry(
                    accountId: $0.accountId, assetId: $0.assetId,
                    timestamp: $0.timestamp, category: $0.category, usdValue: $0.usdValue)
            }
        return PerformanceFeature.computeCategoryChanges(entries: entries)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Categories").font(.headline)
                ForEach(categoryChanges) { change in
                    HStack {
                        Text(change.name).frame(width: 100, alignment: .leading)
                        Text(change.startValue, format: .currency(code: "USD")).frame(width: 100)
                        Text("\u{2192}").foregroundStyle(.secondary)
                        Text(change.endValue, format: .currency(code: "USD")).frame(width: 100)
                        Text(change.percentChange, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(change.percentChange >= 0 ? .green : .red)
                            .frame(width: 60)
                    }
                    .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Asset Prices").font(.headline)
                Text("Top assets with period price change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(height: 200)
    }
}
