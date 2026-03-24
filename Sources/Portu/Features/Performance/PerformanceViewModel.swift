import Foundation
import PortuCore

struct CategorySummaryRow: Identifiable, Equatable, Sendable {
    let category: AssetCategory
    let startValue: Decimal
    let endValue: Decimal

    var id: AssetCategory { category }
    var hasDefinedChangePercent: Bool { startValue != .zero }
    var changeValue: Decimal { endValue - startValue }
    var changePercent: Decimal {
        percentChange(from: startValue, to: endValue)
    }
}

struct AssetPriceRow: Identifiable, Equatable, Sendable {
    let assetID: UUID
    let symbol: String
    let startPrice: Decimal
    let endPrice: Decimal
    let latestValue: Decimal

    var id: UUID { assetID }
    var hasDefinedChangePercent: Bool { startPrice != .zero }
    var changePercent: Decimal {
        percentChange(from: startPrice, to: endPrice)
    }
}

@MainActor
@Observable
final class PerformanceViewModel {
    var selectedMode: PerformanceChartMode = .value
    var selectedRange: PerformanceRange = .oneMonth
    var selectedAccountID: UUID?
    var enabledCategories: Set<AssetCategory> = Set(AssetCategory.allCases)

    let portfolioSnapshots: [PortfolioSnapshot]
    let accountSnapshots: [AccountSnapshot]
    let assetSnapshots: [AssetSnapshot]

    private let calendar: Calendar

    var valuePoints: [PerformancePoint] {
        if let selectedAccountID {
            return filteredAccountSnapshots(for: selectedAccountID).map { snapshot in
                PerformancePoint(
                    date: snapshot.timestamp,
                    value: snapshot.totalValue,
                    usesAccountSnapshot: true
                )
            }
        }

        return filteredPortfolioSnapshots.map { snapshot in
            PerformancePoint(
                date: snapshot.timestamp,
                value: snapshot.totalValue,
                usesAccountSnapshot: false
            )
        }
    }

    var assetStacks: [AssetCategory: [PerformancePoint]] {
        let filteredSnapshots = filteredAssetSnapshots

        return Dictionary(grouping: filteredSnapshots, by: \.category)
            .reduce(into: [AssetCategory: [PerformancePoint]]()) { partialResult, entry in
                let (category, snapshots) = entry
                guard enabledCategories.contains(category) else {
                    return
                }

                let groupedByTimestamp = Dictionary(grouping: snapshots, by: \.timestamp)
                let points = groupedByTimestamp.keys.sorted().map { timestamp in
                    let total = groupedByTimestamp[timestamp, default: []]
                        .reduce(.zero) { partial, snapshot in
                            partial + snapshot.usdValue
                        }

                    return PerformancePoint(
                        date: timestamp,
                        value: total,
                        usesAccountSnapshot: false
                    )
                }

                partialResult[category] = points
            }
    }

    var partialAccountIDs: Set<UUID> {
        if let selectedAccountID {
            let hasStaleSnapshots = filteredAccountSnapshots(for: selectedAccountID)
                .contains { snapshot in
                    snapshot.isFresh == false
                }
            return hasStaleSnapshots ? [selectedAccountID] : []
        }

        let partialBatchIDs = Set(
            filteredPortfolioSnapshots
                .filter(\.isPartial)
                .map(\.syncBatchId)
        )
        guard !partialBatchIDs.isEmpty else {
            return []
        }

        return Set(
            accountSnapshots
                .filter { snapshot in
                    partialBatchIDs.contains(snapshot.syncBatchId) && snapshot.isFresh == false
                }
                .map(\.accountId)
        )
    }

    var currentSeriesContainsPartialSnapshots: Bool {
        !partialAccountIDs.isEmpty
    }

    var pnlBars: [PnLBarPoint] {
        let points = dailyClosingValuePoints
        guard points.count > 1 else {
            return []
        }

        var bars: [PnLBarPoint] = []
        var cumulativeValue = Decimal.zero

        for index in 1..<points.count {
            let previousDate = calendar.startOfDay(for: points[index - 1].date)
            let currentDate = calendar.startOfDay(for: points[index].date)
            let dayGap = calendar.dateComponents([.day], from: previousDate, to: currentDate).day

            guard dayGap == 1 else {
                continue
            }

            let delta = points[index].value - points[index - 1].value
            cumulativeValue += delta

            bars.append(
                PnLBarPoint(
                    date: points[index].date,
                    value: delta,
                    cumulativeValue: cumulativeValue
                )
            )
        }

        return bars
    }

    var categorySummaryRows: [CategorySummaryRow] {
        let snapshots = filteredAssetSnapshots
        guard let startTimestamp = snapshots.map(\.timestamp).min(),
              let endTimestamp = snapshots.map(\.timestamp).max()
        else {
            return []
        }

        let startTotals = categoryTotals(at: startTimestamp, snapshots: snapshots)
        let endTotals = categoryTotals(at: endTimestamp, snapshots: snapshots)
        let categories = Set(startTotals.keys).union(endTotals.keys)

        return categories
            .map { category in
                CategorySummaryRow(
                    category: category,
                    startValue: startTotals[category, default: .zero],
                    endValue: endTotals[category, default: .zero]
                )
            }
            .filter { $0.startValue != .zero || $0.endValue != .zero }
            .sorted { lhs, rhs in
                if lhs.endValue == rhs.endValue {
                    return lhs.category.rawValue < rhs.category.rawValue
                }

                return lhs.endValue > rhs.endValue
            }
    }

    var assetPriceRows: [AssetPriceRow] {
        let snapshots = filteredAssetSnapshots
        guard let startTimestamp = snapshots.map(\.timestamp).min(),
              let endTimestamp = snapshots.map(\.timestamp).max()
        else {
            return []
        }

        return Dictionary(grouping: snapshots, by: \.assetId)
            .compactMap { assetID, assetSnapshots in
                let startSnapshots = assetSnapshots.filter { $0.timestamp == startTimestamp }
                let endSnapshots = assetSnapshots.filter { $0.timestamp == endTimestamp }
                let symbol = (endSnapshots.first ?? assetSnapshots.first)?.symbol ?? "Asset"
                let latestValue = endSnapshots.reduce(.zero) { partial, snapshot in
                    partial + snapshot.usdValue
                }

                guard let endPrice = weightedPrice(for: endSnapshots) else {
                    return nil
                }

                return AssetPriceRow(
                    assetID: assetID,
                    symbol: symbol,
                    startPrice: weightedPrice(for: startSnapshots) ?? .zero,
                    endPrice: endPrice,
                    latestValue: latestValue
                )
            }
            .sorted { lhs, rhs in
                if lhs.latestValue == rhs.latestValue {
                    return lhs.symbol < rhs.symbol
                }

                return lhs.latestValue > rhs.latestValue
            }
    }

    init(
        portfolioSnapshots: [PortfolioSnapshot] = [],
        accountSnapshots: [AccountSnapshot] = [],
        assetSnapshots: [AssetSnapshot] = [],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.portfolioSnapshots = portfolioSnapshots.sorted(by: compareSnapshotDates)
        self.accountSnapshots = accountSnapshots.sorted(by: compareSnapshotDates)
        self.assetSnapshots = assetSnapshots.sorted(by: compareSnapshotDates)
        self.calendar = calendar
    }

    private var filteredPortfolioSnapshots: [PortfolioSnapshot] {
        snapshotsInSelectedRange(portfolioSnapshots, timestamp: \.timestamp)
    }

    private var filteredAssetSnapshots: [AssetSnapshot] {
        let accountFiltered = if let selectedAccountID {
            assetSnapshots.filter { $0.accountId == selectedAccountID }
        } else {
            assetSnapshots
        }

        return snapshotsInSelectedRange(accountFiltered, timestamp: \.timestamp)
    }

    private func filteredAccountSnapshots(
        for accountID: UUID
    ) -> [AccountSnapshot] {
        snapshotsInSelectedRange(
            accountSnapshots.filter { $0.accountId == accountID },
            timestamp: \.timestamp
        )
    }

    private func snapshotsInSelectedRange<Snapshot>(
        _ snapshots: [Snapshot],
        timestamp: KeyPath<Snapshot, Date>
    ) -> [Snapshot] {
        guard let latestTimestamp = snapshots.map({ $0[keyPath: timestamp] }).max() else {
            return []
        }

        return snapshots.filter { snapshot in
            selectedRange.contains(
                snapshot[keyPath: timestamp],
                relativeTo: latestTimestamp,
                calendar: calendar
            )
        }
    }

    private var dailyClosingValuePoints: [PerformancePoint] {
        Dictionary(grouping: valuePoints) { point in
            calendar.startOfDay(for: point.date)
        }
        .values
        .compactMap { dailyPoints in
            dailyPoints.max { lhs, rhs in
                lhs.date < rhs.date
            }
        }
        .sorted { lhs, rhs in
            lhs.date < rhs.date
        }
    }

    private func categoryTotals(
        at timestamp: Date,
        snapshots: [AssetSnapshot]
    ) -> [AssetCategory: Decimal] {
        snapshots
            .filter { $0.timestamp == timestamp }
            .reduce(into: [AssetCategory: Decimal]()) { partialResult, snapshot in
                partialResult[snapshot.category, default: .zero] += snapshot.usdValue
            }
    }

    private func weightedPrice(
        for snapshots: [AssetSnapshot]
    ) -> Decimal? {
        let totalAmount = snapshots.reduce(.zero) { partial, snapshot in
            partial + snapshot.amount
        }
        guard totalAmount != .zero else {
            return nil
        }

        let totalValue = snapshots.reduce(.zero) { partial, snapshot in
            partial + snapshot.usdValue
        }
        return totalValue / totalAmount
    }
}

private func compareSnapshotDates<Snapshot>(
    _ lhs: Snapshot,
    _ rhs: Snapshot,
    timestamp: KeyPath<Snapshot, Date>
) -> Bool {
    lhs[keyPath: timestamp] < rhs[keyPath: timestamp]
}

private func compareSnapshotDates(
    _ lhs: PortfolioSnapshot,
    _ rhs: PortfolioSnapshot
) -> Bool {
    compareSnapshotDates(lhs, rhs, timestamp: \.timestamp)
}

private func compareSnapshotDates(
    _ lhs: AccountSnapshot,
    _ rhs: AccountSnapshot
) -> Bool {
    compareSnapshotDates(lhs, rhs, timestamp: \.timestamp)
}

private func compareSnapshotDates(
    _ lhs: AssetSnapshot,
    _ rhs: AssetSnapshot
) -> Bool {
    compareSnapshotDates(lhs, rhs, timestamp: \.timestamp)
}

private func percentChange(
    from startValue: Decimal,
    to endValue: Decimal
) -> Decimal {
    guard startValue != .zero else {
        return .zero
    }

    return ((endValue - startValue) / startValue) * 100
}
