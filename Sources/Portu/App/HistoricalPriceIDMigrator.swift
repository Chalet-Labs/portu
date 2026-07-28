import Foundation
import PortuCore
import SwiftData

enum HistoricalPriceIDMigrator {
    static let completionDefaultsKey = "migration.historicalPriceIDs.v1.completed"

    private struct CacheKey: Hashable {
        let coinGeckoID: String
        let day: Date
        let currency: FiatCurrency
    }

    @MainActor
    static func migrate(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        fetch: (ModelContext) throws -> [HistoricalPricePoint] = {
            try $0.fetch(FetchDescriptor<HistoricalPricePoint>())
        },
        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard defaults.bool(forKey: completionDefaultsKey) == false else { return }

        let rows = try fetch(modelContext)
        let groupedRows = Dictionary(grouping: rows) { row in
            CacheKey(
                coinGeckoID: OnchainTokenIdentity.normalizedHistoricalPriceID(row.coinGeckoId),
                day: row.day,
                currency: row.fiatCurrency)
        }
        var hasChanges = false

        for (key, candidates) in groupedRows {
            guard
                candidates.count > 1
                || candidates.contains(where: { $0.coinGeckoId != key.coinGeckoID })
            else {
                continue
            }
            let sortedCandidates = candidates.sorted { lhs, rhs in
                if lhs.fetchedAt == rhs.fetchedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.fetchedAt > rhs.fetchedAt
            }
            guard let survivor = sortedCandidates.first else { continue }
            survivor.coinGeckoId = key.coinGeckoID
            for duplicate in sortedCandidates.dropFirst() {
                modelContext.delete(duplicate)
            }
            hasChanges = true
        }

        if hasChanges {
            do {
                try save(modelContext)
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        defaults.set(true, forKey: completionDefaultsKey)
    }
}
