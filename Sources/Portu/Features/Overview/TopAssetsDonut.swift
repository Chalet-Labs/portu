// Sources/Portu/Features/Overview/TopAssetsDonut.swift
import Charts
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct TopAssetsDonut: View {
    let store: StoreOf<AppFeature>
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
        label: (K) -> String) -> [SliceData] {
        aggregated
            .sorted { $0.value > $1.value }
            .prefix(8)
            .enumerated()
            .map { SliceData(
                label: label($0.element.key),
                value: $0.element.value,
                color: chartColor(index: $0.offset)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Assets")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                Spacer()
                Picker("Group", selection: $groupByCategory) {
                    Text("Category").tag(true)
                    Text("Asset").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 136)
                .dashboardControl()
            }

            if slices.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Value", slice.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 1)
                        .foregroundStyle(slice.color)
                        .annotation(position: .overlay) {
                            Text(slice.label)
                                .font(.caption2)
                                .foregroundStyle(PortuTheme.dashboardText)
                        }
                }
                .frame(height: 168)

                // Legend
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label)
                            .font(.caption)
                            .foregroundStyle(PortuTheme.dashboardText)
                        Spacer()
                        Text(slice.value, format: .currency(code: "USD"))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    }
                }
            }

            Button("See all \u{2192}") {
                store.send(.sectionSelected(.allAssets))
            }
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardGold)
            .buttonStyle(.plain)
        }
    }

    private func tokenUSDValue(_ token: PositionToken) -> Decimal {
        token.resolvedUSDValue(prices: appState.prices)
    }

    private func chartColor(index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.360, green: 0.610, blue: 0.700),
            Color(red: 0.930, green: 0.800, blue: 0.280),
            Color(red: 0.400, green: 0.800, blue: 0.730),
            Color(red: 0.760, green: 0.300, blue: 0.250),
            Color(red: 0.830, green: 0.600, blue: 0.230),
            Color(red: 0.900, green: 0.900, blue: 0.840),
            Color(red: 0.480, green: 0.420, blue: 0.720),
            Color(red: 0.650, green: 0.450, blue: 0.320)
        ]
        return colors[index % colors.count]
    }
}
