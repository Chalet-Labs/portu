import Foundation
import PortuCore
import SwiftData

enum HistoricalPriceIDMigrator {
    static let completionDefaultsKey = "migration.historicalPriceIDs.v2.completed"

    private struct CacheKey: Hashable {
        let coinGeckoID: String
        let day: Date
        let currency: FiatCurrency
    }

    @MainActor
    static func migrate(
        in modelContext: ModelContext,
        storeIsEphemeral: Bool = false,
        defaults: UserDefaults = .standard,
        fetch: (ModelContext) throws -> [HistoricalPricePoint] = {
            try $0.fetch(FetchDescriptor<HistoricalPricePoint>())
        },
        fetchAssets: (ModelContext) throws -> [Asset] = {
            try $0.fetch(FetchDescriptor<Asset>())
        },
        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard storeIsEphemeral == false else { return }
        guard defaults.bool(forKey: completionDefaultsKey) == false else { return }

        let solanaPriceIDs = try solanaPriceIDLookup(assets: fetchAssets(modelContext))
        let rows = try fetch(modelContext)
        let groupedRows = Dictionary(grouping: rows) { row in
            let normalizedID = OnchainTokenIdentity.normalizedHistoricalPriceID(row.coinGeckoId)
            return CacheKey(
                coinGeckoID: solanaPriceIDs[normalizedID.lowercased()] ?? normalizedID,
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

    private static func solanaPriceIDLookup(assets: [Asset]) -> [String: String] {
        let groupedIDs = Dictionary(grouping: assets.compactMap { asset -> (String, String)? in
            guard
                let identity = OnchainTokenIdentity(
                    chain: asset.upsertChain,
                    contractAddress: asset.upsertContract),
                identity.chain == .solana
            else {
                return nil
            }
            return (identity.historicalPriceID.lowercased(), identity.historicalPriceID)
        }, by: \.0)

        return groupedIDs.compactMapValues { candidates in
            let canonicalIDs = Set(candidates.map(\.1))
            return canonicalIDs.count == 1 ? canonicalIDs.first : nil
        }
    }
}
