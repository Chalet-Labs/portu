import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// Asset Detail only ever shows one asset, so its query must not load the whole asset table.
@MainActor
struct AssetDetailAssetQueryTests {
    @Test func `descriptor fetches exactly the requested asset`() throws {
        let context = try makeContext()
        let wanted = Asset(symbol: "ETH", name: "Ethereum")
        context.insert(wanted)
        for index in 0 ..< 5 {
            context.insert(Asset(symbol: "T\(index)", name: "Token \(index)"))
        }
        try context.save()

        let fetched = try context.fetch(AssetDetailView.assetDescriptor(id: wanted.id))

        #expect(fetched.map(\.id) == [wanted.id])
    }

    @Test func `descriptor finds nothing for an unknown id`() throws {
        let context = try makeContext()
        for index in 0 ..< 3 {
            context.insert(Asset(symbol: "T\(index)", name: "Token \(index)"))
        }
        try context.save()

        let fetched = try context.fetch(AssetDetailView.assetDescriptor(id: UUID()))

        #expect(fetched.isEmpty)
    }

    @Test func `descriptor asks for at most one row`() {
        #expect(AssetDetailView.assetDescriptor(id: UUID()).fetchLimit == 1)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Asset.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}
