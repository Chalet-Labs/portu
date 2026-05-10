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
        if let existing = overrides.first(where: { $0.assetId == assetId }) {
            override = existing
        } else {
            override = TokenPricingOverride(assetId: assetId)
            modelContext.insert(override)
        }

        update(override)
        override.updatedAt = .now
        do {
            try save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
