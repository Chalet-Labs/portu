import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct AssetHoldingsSummary: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Query private var allTokens: [PositionToken]

    private var summary: HoldingsSummary {
        let entries = allTokens
            .filter { $0.asset?.id == assetId && $0.position?.account?.isActive == true }
            .compactMap { token -> PositionTokenEntry? in
                guard let pos = token.position else { return nil }
                return PositionTokenEntry(
                    tokenId: token.id,
                    accountName: pos.account?.name ?? "Unknown",
                    protocolName: pos.protocolName,
                    positionType: pos.positionType,
                    chain: pos.chain,
                    role: token.role,
                    amount: token.amount,
                    usdValue: token.usdValue,
                    coinGeckoId: token.asset?.coinGeckoId
                )
            }
        return AssetDetailFeature.computeHoldingsSummary(tokens: entries, prices: store.prices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holdings Summary")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Accounts").font(.caption).foregroundStyle(.secondary)
                    Text("\(summary.accountCount)").font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Total Amount").font(.caption).foregroundStyle(.secondary)
                    Text(summary.totalAmount, format: .number.precision(.fractionLength(2 ... 8)))
                        .font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Total Value").font(.caption).foregroundStyle(.secondary)
                    Text(summary.totalValue, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                }
            }

            if !summary.byChain.isEmpty {
                Text("On Networks").font(.subheadline.weight(.medium))
                ForEach(summary.byChain) { chain in
                    HStack {
                        Text(chain.name)
                        Spacer()
                        Text(chain.share, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                        Text(chain.value, format: .currency(code: "USD"))
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.body)
                }
            }
        }
    }
}
