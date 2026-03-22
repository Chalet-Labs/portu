import Foundation
import PortuCore

enum QuerySnapshots {
    static func sortedByTimestamp(
        _ snapshots: [PortfolioSnapshot]
    ) -> [PortfolioSnapshot] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    static func latest(
        _ snapshots: [PortfolioSnapshot]
    ) -> PortfolioSnapshot? {
        sortedByTimestamp(snapshots).last
    }

    static func recent(
        _ snapshots: [PortfolioSnapshot],
        limit: Int
    ) -> [PortfolioSnapshot] {
        guard limit > 0 else {
            return []
        }

        return Array(sortedByTimestamp(snapshots).suffix(limit))
    }
}
