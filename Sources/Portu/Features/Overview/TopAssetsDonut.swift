// Sources/Portu/Features/Overview/TopAssetsDonut.swift
import Charts
import PortuCore
import SwiftData
import SwiftUI

struct TopAssetsDonut: View {
    @Environment(AppState.self) private var appState
    @Query private var tokens: [PositionToken]

    @State private var groupByCategory = true

    /// Only tokens from active accounts
    private var activeTokens: [PositionToken] {
        tokens.filter { $0.position?.account?.isActive == true }
    }

    private struct SliceData: Identifiable {
        let id = UUID()
        let label: String
        let value: Decimal
        let color: Color
    }

    private var slices: [SliceData] {
        if groupByCategory {
            var byCategory: [AssetCategory: Decimal] = [:]
            for token in activeTokens where token.role.isPositive {
                byCategory[token.asset?.category ?? .other, default: 0] += tokenUSDValue(token)
            }
            return buildSlices(from: byCategory) { $0.rawValue.capitalized }
        } else {
            var byAsset: [String: Decimal] = [:]
            for token in activeTokens where token.role.isPositive {
                byAsset[token.asset?.symbol ?? "???", default: 0] += tokenUSDValue(token)
            }
            return buildSlices(from: byAsset) { $0 }
        }
    }

    private func buildSlices<K: Hashable>(
        from aggregated: [K: Decimal],
        label: (K) -> String
    )
        -> [SliceData]
    {
        aggregated
            .sorted { $0.value > $1.value }
            .prefix(8)
            .enumerated()
            .map { SliceData(
                label: label($0.element.key),
                value: $0.element.value,
                color: chartColor(index: $0.offset)
            ) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top Assets")
                    .font(.headline)
                Spacer()
                Picker("Group", selection: $groupByCategory) {
                    Text("Category").tag(true)
                    Text("Asset").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if slices.isEmpty {
                Text("No data").foregroundStyle(.secondary)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Value", slice.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 1
                    )
                    .foregroundStyle(slice.color)
                    .annotation(position: .overlay) {
                        Text(slice.label)
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 180)

                // Legend
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label).font(.caption)
                        Spacer()
                        Text(slice.value, format: .currency(code: "USD")).font(.caption)
                    }
                }
            }

            Button("See all \u{2192}") {
                appState.selectedSection = .allAssets
            }
            .font(.caption)
        }
    }

    private func tokenUSDValue(_ token: PositionToken) -> Decimal {
        token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue
    }

    private func chartColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .yellow, .cyan, .red]
        return colors[index % colors.count]
    }
}
