import Foundation
import PortuCore

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
