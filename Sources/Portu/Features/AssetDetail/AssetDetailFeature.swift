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

    /// Aggregate snapshot entries by day, taking the latest per (day, account) then summing across accounts.
    static func aggregateSnapshots(
        entries: [SnapshotEntry]) -> [ChartDataPoint] {
        let cal = Calendar.current

        // Step 1: For each (day, accountId), keep only the entry with the latest timestamp.
        var latest: [Date: [UUID: SnapshotEntry]] = [:]
        for entry in entries {
            let day = cal.startOfDay(for: entry.timestamp)
            let existing = latest[day, default: [:]][entry.accountId]
            if existing == nil || entry.timestamp > existing!.timestamp {
                latest[day, default: [:]][entry.accountId] = entry
            }
        }

        // Step 2: Sum the deduped entries across accounts per day.
        return latest
            .sorted { $0.key < $1.key }
            .map { date, accounts in
                var gross: Decimal = 0, borrow: Decimal = 0, amt: Decimal = 0, borrowAmt: Decimal = 0
                for entry in accounts.values {
                    gross += entry.grossUSD
                    borrow += entry.borrowUSD
                    amt += entry.grossAmount
                    borrowAmt += entry.borrowAmount
                }
                return ChartDataPoint(
                    date: date,
                    grossUSD: gross,
                    borrowUSD: borrow,
                    grossAmount: amt,
                    borrowAmount: borrowAmt)
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
