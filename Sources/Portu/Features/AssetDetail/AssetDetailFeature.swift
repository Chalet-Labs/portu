import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

enum ChartMode: String, CaseIterable, Equatable, Hashable {
    case price = "Price"
    case dollarValue = "$ Value"
    case amount = "Amount"
}

/// Per-token input for position row aggregation — decouples from SwiftData models.
struct PositionTokenEntry: Equatable {
    let tokenId: UUID
    let accountName: String
    let protocolName: String?
    let positionType: PositionType
    let chain: Chain?
    let role: TokenRole
    let amount: Decimal
    let usdValue: Decimal
    let coinGeckoId: String?

    /// Convert active tokens for a specific asset into PositionTokenEntries.
    static func fromActiveTokens(_ tokens: [PositionToken], assetId: UUID) -> [PositionTokenEntry] {
        tokens
            .filter { $0.asset?.id == assetId && $0.position?.account?.isActive == true }
            .compactMap { token in
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
                    coinGeckoId: token.asset?.coinGeckoId)
            }
    }
}

/// Row data for per-position display in asset detail.
nonisolated struct PositionRowData: Identifiable, Equatable {
    let id: UUID
    let accountName: String
    let platformName: String
    let context: String
    let network: String
    let amount: Decimal
    let usdBalance: Decimal
}

/// Aggregated holdings summary for a single asset.
struct HoldingsSummary: Equatable {
    let totalAmount: Decimal
    let totalValue: Decimal
    let accountCount: Int
    let byChain: [ChainBreakdown]
}

struct ChainBreakdown: Equatable, Identifiable {
    var id: String {
        name
    }

    let name: String
    let share: Decimal
    let value: Decimal
}

/// Lightweight input for snapshot aggregation — decouples from SwiftData @Model.
struct SnapshotEntry: Equatable {
    let accountId: UUID
    let assetId: UUID
    let timestamp: Date
    let grossUSD: Decimal
    let borrowUSD: Decimal
    let grossAmount: Decimal
    let borrowAmount: Decimal
}

/// Aggregated chart data point (one per day).
nonisolated struct ChartDataPoint: Identifiable, Equatable {
    let date: Date
    var id: Date {
        date
    }

    let grossUSD: Decimal
    let borrowUSD: Decimal
    let grossAmount: Decimal
    let borrowAmount: Decimal
}

/// Price info for the asset detail header.
struct AssetPriceInfo: Equatable {
    let price: Decimal
    let change24h: Decimal?
}

// MARK: - AssetDetailFeature

@Reducer
struct AssetDetailFeature {
    @ObservableState
    struct State: Equatable {
        var chartMode: ChartMode = .price
        var selectedRange: ChartTimeRange = .oneMonth
    }

    enum Action: Equatable {
        case chartModeChanged(ChartMode)
        case timeRangeChanged(ChartTimeRange)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .chartModeChanged(mode):
                state.chartMode = mode
                return .none

            case let .timeRangeChanged(range):
                state.selectedRange = range
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Map individual token entries to position rows with live price resolution.
    static func aggregatePositionRows(
        tokens: [PositionTokenEntry],
        prices: [String: Decimal]) -> [PositionRowData] {
        tokens.map { token in
            let usdBalance: Decimal = if let cgId = token.coinGeckoId, let livePrice = prices[cgId] {
                token.amount * livePrice
            } else {
                token.usdValue
            }

            return PositionRowData(
                id: token.tokenId,
                accountName: token.accountName,
                platformName: token.protocolName ?? "Wallet",
                context: token.positionType.rawValue.capitalized,
                network: token.chain?.rawValue.capitalized ?? "Off-chain",
                amount: token.amount,
                usdBalance: usdBalance)
        }
        .sorted { $0.usdBalance > $1.usdBalance }
    }

    /// Compute holdings summary from token entries for a single asset.
    static func computeHoldingsSummary(
        tokens: [PositionTokenEntry],
        prices: [String: Decimal]) -> HoldingsSummary {
        var positiveAmount: Decimal = 0
        var borrowAmount: Decimal = 0
        var positiveUSD: Decimal = 0
        var borrowUSD: Decimal = 0
        var accountNames: Set<String> = []
        let coinGeckoId = tokens.first(where: { $0.coinGeckoId != nil })?.coinGeckoId

        for token in tokens {
            accountNames.insert(token.accountName)
            if token.role.isPositive {
                positiveAmount += token.amount
                positiveUSD += token.usdValue
            } else if token.role.isBorrow {
                borrowAmount += token.amount
                borrowUSD += token.usdValue
            }
        }

        let totalAmount = positiveAmount - borrowAmount
        let totalValue: Decimal = if let cgId = coinGeckoId, let livePrice = prices[cgId] {
            totalAmount * livePrice
        } else {
            positiveUSD - borrowUSD
        }

        // Chain breakdown — positive tokens only
        var chains: [String: (amount: Decimal, value: Decimal)] = [:]
        for token in tokens where token.role.isPositive {
            let chainName = token.chain?.rawValue.capitalized ?? "Off-chain"
            let val: Decimal = if let cgId = token.coinGeckoId, let livePrice = prices[cgId] {
                token.amount * livePrice
            } else {
                token.usdValue
            }
            chains[chainName, default: (0, 0)].amount += token.amount
            chains[chainName, default: (0, 0)].value += val
        }

        let totalPositive = chains.values.reduce(Decimal.zero) { $0 + $1.amount }
        let byChain = chains.map { name, entry in
            let share = totalPositive > 0 ? entry.amount / totalPositive : 0
            return ChainBreakdown(name: name, share: share, value: entry.value)
        }
        .sorted { $0.value > $1.value }

        return HoldingsSummary(
            totalAmount: totalAmount,
            totalValue: totalValue,
            accountCount: accountNames.count,
            byChain: byChain)
    }

    /// Aggregate snapshot entries by day, taking the latest per (day, account, asset) then summing across accounts.
    static func aggregateSnapshots(
        entries: [SnapshotEntry]) -> [ChartDataPoint] {
        let cal = Calendar.current

        // Step 1: For each (day, accountId, assetId), keep only the entry with the latest timestamp.
        struct DedupKey: Hashable {
            let day: Date
            let accountId: UUID
            let assetId: UUID
        }
        var latest: [DedupKey: SnapshotEntry] = [:]
        for entry in entries {
            let key = DedupKey(
                day: cal.startOfDay(for: entry.timestamp),
                accountId: entry.accountId, assetId: entry.assetId)
            if let existing = latest[key], entry.timestamp <= existing.timestamp {
                continue
            }
            latest[key] = entry
        }

        // Step 2: Sum deduped entries across accounts/assets per day.
        var grouped: [Date: (Decimal, Decimal, Decimal, Decimal)] = [:]
        for entry in latest.values {
            let day = cal.startOfDay(for: entry.timestamp)
            var agg = grouped[day] ?? (0, 0, 0, 0)
            agg.0 += entry.grossUSD
            agg.1 += entry.borrowUSD
            agg.2 += entry.grossAmount
            agg.3 += entry.borrowAmount
            grouped[day] = agg
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { date, agg in
                ChartDataPoint(
                    date: date,
                    grossUSD: agg.0,
                    borrowUSD: agg.1,
                    grossAmount: agg.2,
                    borrowAmount: agg.3)
            }
    }

    /// Resolve header price info for an asset.
    static func headerPriceInfo(
        coinGeckoId: String?,
        prices: [String: Decimal],
        changes24h: [String: Decimal]) -> AssetPriceInfo? {
        guard let cgId = coinGeckoId, let price = prices[cgId] else { return nil }
        return AssetPriceInfo(price: price, change24h: changes24h[cgId])
    }
}
