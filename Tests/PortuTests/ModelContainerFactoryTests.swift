import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

@MainActor
struct ModelContainerFactoryTests {
    @Test func `production open failure leaves existing store artifacts intact`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PortuModelContainerFactoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        let walURL = URL(fileURLWithPath: storeURL.path(percentEncoded: false) + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path(percentEncoded: false) + "-shm")
        try Data("wal sentinel".utf8).write(to: walURL)
        try Data("shm sentinel".utf8).write(to: shmURL)

        let factory = ModelContainerFactory(storeURL: storeURL)

        #expect(throws: (any Error).self) {
            _ = try factory.makeForProduction()
        }
        #expect(FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: walURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: shmURL.path(percentEncoded: false)))
    }

    @Test func `legacy historical price store migrates price to a USD row`() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "PortuLegacyPriceMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: directory)
        }

        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        try copyFixture(named: "LegacyHistoricalPrice.store", to: storeURL, fileManager: fileManager)

        let container = try ModelContainerFactory(storeURL: storeURL).makeForProduction()
        let prices = try container.mainContext.fetch(FetchDescriptor<HistoricalPricePoint>())
        let price = try #require(prices.first)
        let expectedPrice = try #require(Decimal(string: "43123.45"))

        #expect(prices.count == 1)
        #expect(price.coinGeckoId == "bitcoin")
        #expect(price.fiatCurrency == .usd)
        #expect(price.price == expectedPrice)
    }

    @Test func `enum historical price currency migrates to raw currency code`() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appending(path: "PortuEnumPriceMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: directory)
        }

        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        try copyFixture(named: "LegacyEnumHistoricalPrice.store", to: storeURL, fileManager: fileManager)

        let container = try ModelContainerFactory(storeURL: storeURL).makeForProduction()
        let prices = try container.mainContext.fetch(FetchDescriptor<HistoricalPricePoint>())
        let price = try #require(prices.first)
        let expectedPrice = try #require(Decimal(string: "39000.50"))

        #expect(prices.count == 1)
        #expect(price.coinGeckoId == "bitcoin")
        #expect(price.fiatCurrency == .chf)
        #expect(price.price == expectedPrice)
    }

    private func copyFixture(named name: String, to destination: URL, fileManager: FileManager) throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/\(name)", directoryHint: .notDirectory)

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: fixture.path(percentEncoded: false) + suffix)
            guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }

            let target = URL(fileURLWithPath: destination.path(percentEncoded: false) + suffix)
            try fileManager.copyItem(at: source, to: target)
        }
    }
}
