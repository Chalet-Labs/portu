import Foundation
import PortuCore
import PortuNetwork

@MainActor
@Observable
final class AssetDetailViewModel {
    var selectedMode: AssetChartMode = .price
    var selectedComparison: AssetComparison?

    let assetID: Asset.ID
    let positions: [Position]
    let assetSnapshots: [AssetSnapshot]
    let partialSyncBatchIDs: Set<UUID>

    let priceSeries: [PerformancePoint]
    let valueSeries: [PerformancePoint]
    let amountSeries: [PerformancePoint]
    let networkRows: [AssetHoldingSummaryRow]
    let positionRows: [AssetDetailPositionRow]
    let accountCount: Int
    let totalAmount: Decimal
    let totalUSDValue: Decimal

    var containsPartialHistory: Bool {
        !partialSyncBatchIDs.isEmpty
    }

    var selectedSeries: [PerformancePoint] {
        switch selectedMode {
        case .price:
            priceSeries
        case .value:
            valueSeries
        case .amount:
            amountSeries
        }
    }

    var priceSummaryLabel: String {
        guard let latestPrice = priceSeries.last?.value else {
            return "Price unavailable"
        }

        return "Price: \(Self.usdCurrencyString(for: latestPrice))"
    }

    var valueSummaryLabel: String {
        labeledCurrencyValue(
            latestSeriesValue(in: valueSeries, fallback: totalUSDValue),
            positiveLabel: "Value",
            negativeLabel: "Debt"
        )
    }

    var amountSummaryLabel: String {
        labeledQuantityValue(
            latestSeriesValue(in: amountSeries, fallback: totalAmount),
            positiveLabel: "Held",
            negativeLabel: "Borrowed"
        )
    }

    var selectedSummaryLabel: String {
        switch selectedMode {
        case .price:
            priceSummaryLabel
        case .value:
            valueSummaryLabel
        case .amount:
            amountSummaryLabel
        }
    }

    init(
        assetID: Asset.ID,
        positions: [Position] = [],
        assetSnapshots: [AssetSnapshot] = [],
        historicalPrices: [HistoricalPricePoint] = [],
        portfolioSnapshots: [PortfolioSnapshot] = []
    ) {
        let visiblePositions = positions
            .filter { $0.account?.isActive == true }
            .filter { position in
                position.tokens.contains { token in
                    token.role != .reward && token.asset?.id == assetID
                }
            }
        let visibleAccountIDs = Set(
            visiblePositions.compactMap { $0.account?.id }
        )
        let matchingSnapshots = assetSnapshots
            .filter { snapshot in
                snapshot.assetId == assetID
                    && visibleAccountIDs.contains(snapshot.accountId)
            }
            .sorted(by: compareSnapshotDates)
        let partialSyncBatchIDs = Set(
            portfolioSnapshots
                .filter { snapshot in
                    matchingSnapshots.contains(where: { $0.syncBatchId == snapshot.syncBatchId })
                        && snapshot.isPartial
                }
                .map(\.syncBatchId)
        )
        let positionRows = Self.makePositionRows(
            assetID: assetID,
            positions: visiblePositions
        )

        self.assetID = assetID
        self.positions = visiblePositions
        self.assetSnapshots = matchingSnapshots
        self.partialSyncBatchIDs = partialSyncBatchIDs
        priceSeries = Self.makePriceSeries(historicalPrices)
        valueSeries = Self.makeSeries(
            snapshots: matchingSnapshots,
            portfolioSnapshots: portfolioSnapshots,
            value: { $0.usdValue - $0.borrowUsdValue }
        )
        amountSeries = Self.makeSeries(
            snapshots: matchingSnapshots,
            portfolioSnapshots: portfolioSnapshots,
            value: { $0.amount - $0.borrowAmount }
        )
        networkRows = Self.makeNetworkRows(
            assetID: assetID,
            positions: visiblePositions
        )
        self.positionRows = positionRows
        accountCount = visibleAccountIDs.count
        totalAmount = positionRows.reduce(.zero) { partial, row in
            partial + row.amount
        }
        totalUSDValue = positionRows.reduce(.zero) { partial, row in
            partial + row.usdBalance
        }
    }

    private func latestSeriesValue(
        in series: [PerformancePoint],
        fallback: Decimal
    ) -> Decimal {
        series.last?.value ?? fallback
    }

    private func labeledCurrencyValue(
        _ value: Decimal,
        positiveLabel: String,
        negativeLabel: String
    ) -> String {
        let isNegative = value < .zero
        let label = isNegative ? negativeLabel : positiveLabel
        let displayValue = isNegative ? Self.absoluteValue(of: value) : value

        return "\(label): \(Self.usdCurrencyString(for: displayValue))"
    }

    private func labeledQuantityValue(
        _ value: Decimal,
        positiveLabel: String,
        negativeLabel: String
    ) -> String {
        let isNegative = value < .zero
        let label = isNegative ? negativeLabel : positiveLabel
        let displayValue = isNegative ? Self.absoluteValue(of: value) : value

        return "\(label): \(displayValue.formatted())"
    }

    private struct PositionAssetTotals {
        var amount: Decimal = .zero
        var usdValue: Decimal = .zero
    }

    private struct NetworkAggregate {
        let id: String
        let networkName: String
        var amount: Decimal = .zero
        var usdValue: Decimal = .zero
    }

    private static let usdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func makeSeries(
        snapshots: [AssetSnapshot],
        portfolioSnapshots: [PortfolioSnapshot],
        value: (AssetSnapshot) -> Decimal
    ) -> [PerformancePoint] {
        Dictionary(grouping: snapshots, by: \.syncBatchId)
            .map { batchID, batchSnapshots in
                let timestamp = batchTimestamp(
                    for: batchID,
                    snapshots: batchSnapshots,
                    portfolioSnapshots: portfolioSnapshots
                )
                let total = batchSnapshots.reduce(.zero) { partial, snapshot in
                    partial + value(snapshot)
                }

                return PerformancePoint(
                    date: timestamp,
                    value: total,
                    usesAccountSnapshot: false
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func usdCurrencyString(
        for value: Decimal
    ) -> String {
        let amount = usdFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
        return "$\(amount)"
    }

    private static func makePriceSeries(
        _ historicalPrices: [HistoricalPricePoint]
    ) -> [PerformancePoint] {
        historicalPrices
            .map { point in
                PerformancePoint(
                    date: point.date,
                    value: point.price,
                    usesAccountSnapshot: false
                )
            }
            .sorted { $0.date < $1.date }
    }

    private static func batchTimestamp(
        for batchID: UUID,
        snapshots: [AssetSnapshot],
        portfolioSnapshots: [PortfolioSnapshot]
    ) -> Date {
        if let timestamp = portfolioSnapshots.first(where: { $0.syncBatchId == batchID })?.timestamp {
            return timestamp
        }

        return snapshots.map(\.timestamp).max() ?? .distantPast
    }

    private static func makeNetworkRows(
        assetID: Asset.ID,
        positions: [Position]
    ) -> [AssetHoldingSummaryRow] {
        let aggregates = positions.reduce(into: [String: NetworkAggregate]()) { partialResult, position in
            let totals = assetTotals(
                for: assetID,
                in: position
            )
            guard totals.amount != .zero || totals.usdValue != .zero else {
                return
            }

            let id = networkBucketID(for: position.chain)
            var aggregate = partialResult[id] ?? NetworkAggregate(
                id: id,
                networkName: networkTitle(for: position.chain)
            )
            aggregate.amount += totals.amount
            aggregate.usdValue += totals.usdValue
            partialResult[id] = aggregate
        }

        let totalAbsoluteValue = aggregates.values.reduce(.zero) { partial, aggregate in
            partial + absoluteValue(of: aggregate.usdValue)
        }

        return aggregates.values
            .map { aggregate in
                AssetHoldingSummaryRow(
                    id: aggregate.id,
                    networkName: aggregate.networkName,
                    amount: aggregate.amount,
                    share: totalAbsoluteValue == .zero
                        ? .zero
                        : absoluteValue(of: aggregate.usdValue) / totalAbsoluteValue * 100,
                    usdValue: aggregate.usdValue
                )
            }
            .sorted(by: compareNetworkRows)
    }

    private static func makePositionRows(
        assetID: Asset.ID,
        positions: [Position]
    ) -> [AssetDetailPositionRow] {
        positions
            .compactMap { position in
                let totals = assetTotals(
                    for: assetID,
                    in: position
                )
                guard totals.amount != .zero || totals.usdValue != .zero else {
                    return nil
                }

                return AssetDetailPositionRow(
                    id: position.id,
                    accountName: position.account?.name ?? "Unknown Account",
                    platformName: platformName(for: position),
                    contextLabel: contextLabel(for: position.positionType),
                    networkName: networkTitle(for: position.chain),
                    amount: totals.amount,
                    usdBalance: totals.usdValue
                )
            }
            .sorted(by: comparePositionRows)
    }

    private static func assetTotals(
        for assetID: Asset.ID,
        in position: Position
    ) -> PositionAssetTotals {
        position.tokens.reduce(into: PositionAssetTotals()) { partialResult, token in
            guard token.asset?.id == assetID else {
                return
            }

            switch token.role {
            case .borrow:
                partialResult.amount -= token.amount
                partialResult.usdValue -= token.usdValue
            case .balance, .supply, .stake, .lpToken:
                partialResult.amount += token.amount
                partialResult.usdValue += token.usdValue
            case .reward:
                break
            }
        }
    }

    private static func networkBucketID(
        for chain: Chain?
    ) -> String {
        chain?.rawValue ?? "off-chain-custodial"
    }

    private static func networkTitle(
        for chain: Chain?
    ) -> String {
        chain?.rawValue.capitalized ?? "Off-chain / Custodial"
    }

    private static func platformName(
        for position: Position
    ) -> String {
        if let protocolName = position.protocolName,
           protocolName.isEmpty == false {
            return protocolName
        }

        return position.account?.name ?? "Unknown Platform"
    }

    private static func contextLabel(
        for positionType: PositionType
    ) -> String {
        switch positionType {
        case .idle:
            "Idle"
        case .lending:
            "Lending"
        case .liquidityPool:
            "Liquidity Pool"
        case .staking:
            "Staked"
        case .farming:
            "Farming"
        case .vesting:
            "Vesting"
        case .other:
            "Other"
        }
    }

    private static func absoluteValue(
        of value: Decimal
    ) -> Decimal {
        value < .zero ? -value : value
    }

    private static func compareNetworkRows(
        _ lhs: AssetHoldingSummaryRow,
        _ rhs: AssetHoldingSummaryRow
    ) -> Bool {
        let lhsMagnitude = absoluteValue(of: lhs.usdValue)
        let rhsMagnitude = absoluteValue(of: rhs.usdValue)

        if lhsMagnitude == rhsMagnitude {
            if lhs.usdValue == rhs.usdValue {
                return lhs.networkName.localizedCaseInsensitiveCompare(rhs.networkName) == .orderedAscending
            }

            return lhs.usdValue > rhs.usdValue
        }

        return lhsMagnitude > rhsMagnitude
    }

    private static func comparePositionRows(
        _ lhs: AssetDetailPositionRow,
        _ rhs: AssetDetailPositionRow
    ) -> Bool {
        if lhs.usdBalance == rhs.usdBalance {
            if lhs.accountName == rhs.accountName {
                if lhs.networkName == rhs.networkName {
                    if lhs.platformName == rhs.platformName {
                        if lhs.contextLabel == rhs.contextLabel {
                            return lhs.id.uuidString < rhs.id.uuidString
                        }

                        return lhs.contextLabel.localizedCaseInsensitiveCompare(rhs.contextLabel) == .orderedAscending
                    }

                    return lhs.platformName.localizedCaseInsensitiveCompare(rhs.platformName) == .orderedAscending
                }

                return lhs.networkName.localizedCaseInsensitiveCompare(rhs.networkName) == .orderedAscending
            }

            return lhs.accountName.localizedCaseInsensitiveCompare(rhs.accountName) == .orderedAscending
        }

        return lhs.usdBalance > rhs.usdBalance
    }
}

private func compareSnapshotDates(
    _ lhs: AssetSnapshot,
    _ rhs: AssetSnapshot
) -> Bool {
    lhs.timestamp < rhs.timestamp
}
