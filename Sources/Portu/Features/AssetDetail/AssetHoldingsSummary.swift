import SwiftUI
import SwiftData
import PortuCore

struct AssetHoldingsSummary: View {
    let assetId: UUID

    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    private var assetTokens: [PositionToken] {
        allTokens.filter { $0.asset?.id == assetId }
    }

    private var totalAmount: Decimal {
        assetTokens.reduce(Decimal.zero) { sum, t in
            if t.role.isPositive { return sum + t.amount }
            if t.role.isBorrow { return sum - t.amount }
            return sum
        }
    }

    private var totalValue: Decimal {
        if let cgId = assetTokens.first?.asset?.coinGeckoId, let price = appState.prices[cgId] {
            return totalAmount * price
        }
        return assetTokens.reduce(Decimal.zero) { sum, t in
            if t.role.isPositive { return sum + t.usdValue }
            if t.role.isBorrow { return sum - t.usdValue }
            return sum
        }
    }

    private var accountCount: Int {
        Set(assetTokens.compactMap { $0.position?.account?.id }).count
    }

    /// Group by Position.chain (not Asset.upsertChain)
    private var byChain: [(String, Decimal, Decimal)] {
        var chains: [String: (amount: Decimal, value: Decimal)] = [:]
        for token in assetTokens where token.role.isPositive {
            let chainName = token.position?.chain?.rawValue.capitalized ?? "Off-chain"
            let val = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
                ?? token.usdValue
            chains[chainName, default: (0, 0)].amount += token.amount
            chains[chainName, default: (0, 0)].value += val
        }
        let total = chains.values.reduce(Decimal.zero) { $0 + $1.amount }
        return chains.map { (name, entry) in
            let share = total > 0 ? entry.amount / total : 0
            return (name, share, entry.value)
        }
        .sorted { $0.2 > $1.2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holdings Summary")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Accounts").font(.caption).foregroundStyle(.secondary)
                    Text("\(accountCount)").font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Total Amount").font(.caption).foregroundStyle(.secondary)
                    Text(totalAmount, format: .number.precision(.fractionLength(2...8)))
                        .font(.title3.weight(.semibold))
                }
                VStack(alignment: .leading) {
                    Text("Total Value").font(.caption).foregroundStyle(.secondary)
                    Text(totalValue, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                }
            }

            if !byChain.isEmpty {
                Text("On Networks").font(.subheadline.weight(.medium))
                ForEach(byChain, id: \.0) { (chain, share, value) in
                    HStack {
                        Text(chain)
                        Spacer()
                        Text(share, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                        Text(value, format: .currency(code: "USD"))
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.body)
                }
            }
        }
    }
}
