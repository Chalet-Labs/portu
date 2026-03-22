// Sources/Portu/Features/Overview/TopAssetsDonut.swift
import SwiftUI
import SwiftData
import Charts
import PortuCore

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
            // Group by AssetCategory
            var byCategory: [AssetCategory: Decimal] = [:]
            for token in activeTokens where token.role.isPositive {
                let cat = token.asset?.category ?? .other
                let value = tokenUSDValue(token)
                byCategory[cat, default: 0] += value
            }
            return byCategory
                .sorted { $0.value > $1.value }
                .prefix(8)
                .enumerated()
                .map { SliceData(label: $0.element.key.rawValue.capitalized,
                                  value: $0.element.value,
                                  color: chartColor(index: $0.offset)) }
        } else {
            // Group by Asset
            var byAsset: [String: Decimal] = [:]
            for token in activeTokens where token.role.isPositive {
                let symbol = token.asset?.symbol ?? "???"
                byAsset[symbol, default: 0] += tokenUSDValue(token)
            }
            return byAsset
                .sorted { $0.value > $1.value }
                .prefix(8)
                .enumerated()
                .map { SliceData(label: $0.element.key,
                                  value: $0.element.value,
                                  color: chartColor(index: $0.offset)) }
        }
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
                // Navigate to All Assets -- handled via appState.selectedSection
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
