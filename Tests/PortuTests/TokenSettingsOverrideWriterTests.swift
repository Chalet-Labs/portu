import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

struct TokenSettingsOverrideWriterTests {
    @Test func `override draft changes when override fields change with the same id`() {
        let id = UUID()
        let assetId = UUID()
        let first = TokenPricingOverrideSnapshot(
            id: id,
            assetId: assetId,
            manualPriceUSD: 1,
            coinGeckoIdOverride: "old",
            notes: "first")
        let second = TokenPricingOverrideSnapshot(
            id: id,
            assetId: assetId,
            manualPriceUSD: 2,
            coinGeckoIdOverride: "new",
            notes: "second")

        #expect(TokenSettingsOverrideDraft(override: first) != TokenSettingsOverrideDraft(override: second))
    }

    @MainActor
    @Test func `override upsert rolls back existing override without discarding unrelated edits`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let assetId = UUID()
        let override = TokenPricingOverride(assetId: assetId, manualPriceUSD: 1)
        let category = PortfolioCategory(name: "Original", sortOrder: 0)
        context.insert(override)
        context.insert(category)
        try context.save()
        category.name = "Unsaved edit"

        do {
            try TokenPricingOverrideWriter.upsert(
                assetId: assetId,
                overrides: [override],
                in: context) {
                    throw TestSaveError.expected
                } update: { existing in
                    existing.manualPriceUSD = 42
                }
            Issue.record("Expected override upsert to rethrow the save failure.")
        } catch let error as TestSaveError {
            #expect(error == .expected)
            let fetched = try #require(try context.fetch(FetchDescriptor<TokenPricingOverride>()).first)
            #expect(fetched.manualPriceUSD == 1)
            #expect(category.name == "Unsaved edit")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func `override upsert collapses duplicate overrides for an asset`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let assetId = UUID()
        let canonical = TokenPricingOverride(assetId: assetId, manualPriceUSD: 1, notes: "canonical")
        let duplicate = TokenPricingOverride(assetId: assetId, manualPriceUSD: 2, notes: "duplicate")
        context.insert(canonical)
        context.insert(duplicate)

        try TokenPricingOverrideWriter.upsert(
            assetId: assetId,
            overrides: [canonical, duplicate],
            in: context) {
                // Avoid SwiftData's uniqueness save path here; the writer behavior under test is the in-context collapse.
            } update: { override in
                override.manualPriceUSD = 3
                override.notes = "updated"
            }

        let overrides = try context.fetch(FetchDescriptor<TokenPricingOverride>())
            .filter { $0.assetId == assetId }
        #expect(overrides.count == 1)
        #expect(overrides.first?.manualPriceUSD == 3)
        #expect(overrides.first?.notes == "updated")
    }

    @MainActor
    @Test func `override upsert restores duplicate overrides when save fails`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let assetId = UUID()
        let canonical = TokenPricingOverride(assetId: assetId, manualPriceUSD: 1, notes: "canonical")
        let duplicate = TokenPricingOverride(assetId: assetId, manualPriceUSD: 2, notes: "duplicate")
        context.insert(canonical)
        context.insert(duplicate)

        do {
            try TokenPricingOverrideWriter.upsert(
                assetId: assetId,
                overrides: [canonical, duplicate],
                in: context) {
                    throw TestSaveError.expected
                } update: { override in
                    override.manualPriceUSD = 3
                    override.notes = "updated"
                }
            Issue.record("Expected duplicate override save failure to be rethrown.")
        } catch let error as TestSaveError {
            #expect(error == .expected)
            let overrides = try context.fetch(FetchDescriptor<TokenPricingOverride>())
                .filter { $0.assetId == assetId }
                .sorted { $0.notes < $1.notes }
            #expect(overrides.count == 2)
            #expect(overrides.map(\.manualPriceUSD) == [1, 2])
            #expect(overrides.map(\.notes) == ["canonical", "duplicate"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func `override remove restores override without discarding unrelated edits`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let assetId = UUID()
        let override = TokenPricingOverride(assetId: assetId, manualPriceUSD: 1)
        let category = PortfolioCategory(name: "Original", sortOrder: 0)
        context.insert(override)
        context.insert(category)
        try context.save()
        category.name = "Unsaved edit"

        do {
            try TokenPricingOverrideWriter.remove(
                assetId: assetId,
                overrides: [override],
                in: context) {
                    throw TestSaveError.expected
                }
            Issue.record("Expected override remove to rethrow the save failure.")
        } catch let error as TestSaveError {
            #expect(error == .expected)
            let fetched = try #require(try context.fetch(FetchDescriptor<TokenPricingOverride>()).first)
            #expect(fetched.assetId == assetId)
            #expect(fetched.manualPriceUSD == 1)
            #expect(category.name == "Unsaved edit")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private enum TestSaveError: Error, Equatable {
        case expected
    }
}
