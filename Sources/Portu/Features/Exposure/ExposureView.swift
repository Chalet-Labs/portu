import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct ExposureView: View {
    let store: StoreOf<AppFeature>

    @Query private var allTokens: [PositionToken]

    private var tokenEntries: [TokenEntry] {
        allTokens.compactMap { token -> TokenEntry? in
            guard let asset = token.asset, token.position?.account?.isActive == true else { return nil }
            return TokenEntry(
                assetId: asset.id,
                symbol: asset.symbol,
                name: asset.name,
                category: asset.category,
                coinGeckoId: asset.coinGeckoId,
                role: token.role,
                amount: token.amount,
                usdValue: token.usdValue,
            )
        }
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
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    summaryCard("Spot Total", value: summary.totalSpot)
                    summaryCard("Derivatives", value: 0, subtitle: "Coming soon")
                    summaryCard("Net Exposure", value: summary.netExposure, subtitle: "Excl. stablecoins")
                }

                Picker("View", selection: Binding(
                    get: { store.exposure.showByAsset },
                    set: { store.send(.exposure(.viewModeChanged($0))) },
                )) {
                    Text("By Category").tag(false)
                    Text("By Asset").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if store.exposure.showByAsset {
                    assetTable
                } else {
                    categoryTable
                }
            }
            .padding()
        }
        .navigationTitle("Exposure")
    }

    // MARK: - Tables

    private var categoryTable: some View {
        Table(byCategory) {
            TableColumn("Category") { row in Text(row.name).fontWeight(.medium) }
                .width(min: 100, ideal: 140)
            TableColumn("Spot Assets") { row in
                Text(row.spotAssets, format: .currency(code: "USD"))
            }
            .width(min: 80, ideal: 120)
            TableColumn("Liabilities") { row in
                Text(row.liabilities, format: .currency(code: "USD"))
                    .foregroundStyle(row.liabilities > 0 ? .red : .secondary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Spot Net") { row in
                Text(row.spotNet, format: .currency(code: "USD"))
                    .foregroundStyle(row.spotNet < 0 ? .red : .primary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Derivatives") { _ in Text("\u{2014}").foregroundStyle(.tertiary) }
                .width(min: 60, ideal: 80)
            TableColumn("Net Exposure") { row in
                Text(row.netExposure, format: .currency(code: "USD"))
                    .fontWeight(.medium)
            }
            .width(min: 80, ideal: 120)
        }
    }

    private var assetTable: some View {
        Table(byAsset) {
            TableColumn("Asset") { row in Text(row.symbol).fontWeight(.medium) }
                .width(min: 60, ideal: 80)
            TableColumn("Category") { row in
                Text(row.category.rawValue.capitalized)
                    .font(.caption)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Spot Assets") { row in
                Text(row.spotAssets, format: .currency(code: "USD"))
            }
            TableColumn("Liabilities") { row in
                Text(row.liabilities, format: .currency(code: "USD"))
                    .foregroundStyle(row.liabilities > 0 ? .red : .secondary)
            }
            TableColumn("Spot Net") { row in
                Text(row.spotNet, format: .currency(code: "USD"))
                    .foregroundStyle(row.spotNet < 0 ? .red : .primary)
            }
            TableColumn("Net Exposure") { row in
                Text(row.netExposure, format: .currency(code: "USD"))
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Helpers

    private func summaryCard(_ title: String, value: Decimal, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
