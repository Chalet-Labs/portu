import Foundation
import PortuCore
import SwiftData

@MainActor
enum TokenPricingOverrideWriter {
    static func upsert(
        assetId: UUID,
        overrides: [TokenPricingOverride],
        in modelContext: ModelContext,
        update: (TokenPricingOverride) -> Void) throws {
        try upsert(
            assetId: assetId,
            overrides: overrides,
            in: modelContext) {
                try modelContext.save()
            } update: { override in
                update(override)
            }
    }

    static func upsert(
        assetId: UUID,
        overrides: [TokenPricingOverride],
        in modelContext: ModelContext,
        save: () throws -> Void,
        update: (TokenPricingOverride) -> Void) throws {
        let override: TokenPricingOverride
        let previous: Snapshot?
        if let existing = overrides.first(where: { $0.assetId == assetId }) {
            override = existing
            previous = Snapshot(existing)
        } else {
            override = TokenPricingOverride(assetId: assetId)
            modelContext.insert(override)
            previous = nil
        }

        update(override)
        override.updatedAt = .now
        do {
            try save()
        } catch {
            if let previous {
                previous.restore(override)
            } else {
                modelContext.delete(override)
            }
            throw error
        }
    }

    static func remove(
        assetId: UUID,
        overrides: [TokenPricingOverride],
        in modelContext: ModelContext) throws {
        try remove(
            assetId: assetId,
            overrides: overrides,
            in: modelContext) {
                try modelContext.save()
            }
    }

    static func remove(
        assetId: UUID,
        overrides: [TokenPricingOverride],
        in modelContext: ModelContext,
        save: () throws -> Void) throws {
        let removed = overrides.filter { $0.assetId == assetId }
        let snapshots = removed.map(Snapshot.init)
        for override in removed {
            modelContext.delete(override)
        }

        do {
            try save()
        } catch {
            for snapshot in snapshots {
                modelContext.insert(snapshot.makeOverride())
            }
            throw error
        }
    }

    private struct Snapshot {
        let id: UUID
        let assetId: UUID
        let manualPriceUSD: Decimal?
        let coinGeckoIdOverride: String?
        let isIgnored: Bool
        let alwaysShow: Bool
        let notes: String
        let createdAt: Date
        let updatedAt: Date

        init(_ override: TokenPricingOverride) {
            self.id = override.id
            self.assetId = override.assetId
            self.manualPriceUSD = override.manualPriceUSD
            self.coinGeckoIdOverride = override.coinGeckoIdOverride
            self.isIgnored = override.isIgnored
            self.alwaysShow = override.alwaysShow
            self.notes = override.notes
            self.createdAt = override.createdAt
            self.updatedAt = override.updatedAt
        }

        func restore(_ override: TokenPricingOverride) {
            override.id = id
            override.assetId = assetId
            override.manualPriceUSD = manualPriceUSD
            override.coinGeckoIdOverride = coinGeckoIdOverride
            override.isIgnored = isIgnored
            override.alwaysShow = alwaysShow
            override.notes = notes
            override.createdAt = createdAt
            override.updatedAt = updatedAt
        }

        func makeOverride() -> TokenPricingOverride {
            TokenPricingOverride(
                id: id,
                assetId: assetId,
                manualPriceUSD: manualPriceUSD,
                coinGeckoIdOverride: coinGeckoIdOverride,
                isIgnored: isIgnored,
                alwaysShow: alwaysShow,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt)
        }
    }
}
