import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// The live client against the real framework: `didSave` userInfo and entity names are
/// SwiftData's, so these tests save real models instead of posting made-up notifications.
/// Every test filters on its own container, which keeps them independent even though they
/// share the default notification center.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ModelSaveClientTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test func `a main context save reports the entity it touched`() async throws {
        let container = try makeContainer()
        var saves = ModelSaveClient.live(container: container).saves().makeAsyncIterator()

        container.mainContext.insert(PortfolioCategory(name: "Custom", sortOrder: 0))
        try container.mainContext.save()

        #expect(await saves.next() == .entities(["PortfolioCategory"]))
    }

    @Test func `inserts updates and deletes are all reported`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var saves = ModelSaveClient.live(container: container).saves().makeAsyncIterator()

        let category = PortfolioCategory(name: "Custom", sortOrder: 0)
        context.insert(category)
        try context.save()
        #expect(await saves.next() == .entities(["PortfolioCategory"]))

        category.name = "Renamed"
        try context.save()
        #expect(await saves.next() == .entities(["PortfolioCategory"]))

        context.delete(category)
        try context.save()
        #expect(await saves.next() == .entities(["PortfolioCategory"]))
    }

    @Test func `one save touching several entities reports all of them`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var saves = ModelSaveClient.live(container: container).saves().makeAsyncIterator()

        context.insert(PortfolioCategory(name: "Custom", sortOrder: 0))
        context.insert(Account(name: "Main", kind: .manual, dataSource: .manual))
        try context.save()

        #expect(await saves.next() == .entities(["PortfolioCategory", "Account"]))
    }

    @Test func `a save from another context of the same container is reported`() async throws {
        let container = try makeContainer()
        var saves = ModelSaveClient.live(container: container).saves().makeAsyncIterator()

        // Sync, backfill and cache writers save through contexts of their own, so the
        // notification's object is never the main context.
        let writer = ModelContext(container)
        writer.insert(PortfolioCategory(name: "Written elsewhere", sortOrder: 1))
        try writer.save()

        #expect(await saves.next() == .entities(["PortfolioCategory"]))
    }

    @Test func `a save from a background model actor is reported`() async throws {
        let container = try makeContainer()
        var saves = ModelSaveClient.live(container: container).saves().makeAsyncIterator()
        let writer = await BackgroundWriter.make(container: container)

        let ranOnMainThread = try await writer.insertCategory()

        #expect(!ranOnMainThread, "The save has to cross threads for this test to prove anything")
        #expect(await saves.next() == .entities(["PortfolioCategory"]))
    }

    @Test func `saves to a different container are ignored`() async throws {
        let observed = try makeContainer()
        let other = try makeContainer()
        var saves = ModelSaveClient.live(container: observed).saves().makeAsyncIterator()

        other.mainContext.insert(Account(name: "Elsewhere", kind: .manual, dataSource: .manual))
        try other.mainContext.save()
        observed.mainContext.insert(PortfolioCategory(name: "Mine", sortOrder: 0))
        try observed.mainContext.save()

        // The other container saved first, so seeing only this event proves it was filtered out.
        #expect(await saves.next() == .entities(["PortfolioCategory"]))
    }
}

/// Saves the way sync and the cache writers do: through a `@ModelActor` whose context lives on
/// a queue of its own. It is built on a dispatch queue because a `@ModelActor` binds its
/// executor to wherever it is initialized, and a main-actor test would pin it to the main thread.
@ModelActor
private actor BackgroundWriter {
    static func make(container: ModelContainer) async -> BackgroundWriter {
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "ModelSaveClientTests.background-writer").async {
                continuation.resume(returning: BackgroundWriter(modelContainer: container))
            }
        }
    }

    /// Returns whether the save ran on the main thread.
    func insertCategory() throws -> Bool {
        modelContext.insert(PortfolioCategory(name: "Written in the background", sortOrder: 1))
        try modelContext.save()
        return Thread.isMainThread
    }
}

struct ModelSaveEventTests {
    @Test func `an unscoped save touches any entity set`() {
        #expect(ModelSaveEvent.all.touches(["Asset"]))
    }

    @Test func `an entity save touches only the sets it overlaps`() {
        let event = ModelSaveEvent.entities(["Asset", "Account"])

        #expect(event.touches(["Asset", "Position"]))
        #expect(!event.touches(["Position", "PositionToken"]))
    }

    @Test func `a save without identifiers is unscoped`() {
        #expect(ModelSaveEvent(userInfo: nil) == .all)
        #expect(ModelSaveEvent(userInfo: [:]) == .all)
    }

    @Test func `a save that invalidated every identifier is unscoped`() {
        let userInfo: [AnyHashable: Any] = [
            ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue: true
        ]

        #expect(ModelSaveEvent(userInfo: userInfo) == .all)
    }

    @MainActor
    @Test func `identifiers from every change kind map to their entity names`() throws {
        let container = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let category = PortfolioCategory(name: "Custom", sortOrder: 0)
        let account = Account(name: "Main", kind: .manual, dataSource: .manual)
        let rule = CategorySymbolRule(normalizedSymbol: "ETH", category: category)
        container.mainContext.insert(category)
        container.mainContext.insert(account)
        container.mainContext.insert(rule)
        try container.mainContext.save()

        let userInfo: [AnyHashable: Any] = [
            ModelContext.NotificationKey.insertedIdentifiers.rawValue: [category.persistentModelID],
            ModelContext.NotificationKey.updatedIdentifiers.rawValue: [account.persistentModelID],
            ModelContext.NotificationKey.deletedIdentifiers.rawValue: [rule.persistentModelID]
        ]

        #expect(ModelSaveEvent(userInfo: userInfo) == .entities([
            "PortfolioCategory",
            "Account",
            "CategorySymbolRule"
        ]))
    }
}
