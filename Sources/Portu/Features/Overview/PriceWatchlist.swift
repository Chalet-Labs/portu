// Sources/Portu/Features/Overview/PriceWatchlist.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct PriceWatchlist: View {
    @Environment(AppState.self) private var appState
    @Query private var assets: [Asset]

    /// Top assets by portfolio value (those with coinGeckoId for live pricing)
    private var watchlistAssets: [Asset] {
        assets
            .filter { $0.coinGeckoId != nil }
            .sorted { (appState.prices[$0.coinGeckoId!] ?? 0) > (appState.prices[$1.coinGeckoId!] ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prices")
                .font(.headline)

            ForEach(watchlistAssets, id: \.id) { asset in
                HStack {
                    Text(asset.symbol)
                        .fontWeight(.medium)
                    Spacer()

                    if let cgId = asset.coinGeckoId, let price = appState.prices[cgId] {
                        VStack(alignment: .trailing) {
                            Text(price, format: .currency(code: "USD"))
                                .font(.body)
                            if let change = appState.priceChanges24h[cgId] {
                                HStack(spacing: 2) {
                                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    Text(change, format: .percent.precision(.fractionLength(2)))
                                }
                                .font(.caption)
                                .foregroundStyle(PortuTheme.changeColor(for: change))
                            }
                        }
                    } else {
                        Text("\u{2014}").foregroundStyle(.tertiary)
                    }
                }
                Divider()
            }
        }
    }
}
