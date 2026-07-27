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

    @Test func `bootstrap logs the failure and falls back to an in-memory container`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PortuModelContainerFactoryBootstrapTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)

        let factory = ModelContainerFactory(storeURL: storeURL)
        var loggedError: (any Error)?

        let result = try factory.bootstrap { error in
            loggedError = error
        }

        #expect(result.isEphemeral == true)
        #expect(loggedError != nil)
        #expect(FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)))
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

    @Test func `persisted Zapper wallet migration is idempotent and preserves account graph`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PortuZapperMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        let factory = ModelContainerFactory(storeURL: storeURL)
        let walletID = UUID()
        let positionID = UUID()
        let assetID = UUID()

        do {
            let container = try factory.makeForProduction()
            let context = container.mainContext
            let asset = Asset(id: assetID, symbol: "ETH", name: "Ethereum")
            let token = PositionToken(role: .balance, amount: 1, usdValue: 2000, asset: asset)
            let position = Position(id: positionID, positionType: .idle, netUSDValue: 2000, tokens: [token])
            let wallet = Account(
                id: walletID,
                name: "Legacy",
                kind: .wallet,
                dataSource: .zapper,
                positions: [position])
            let address = WalletAddress(chain: nil, address: "0xabc", account: wallet)
            wallet.addresses = [address]
            context.insert(wallet)
            context.insert(Account(name: "Manual", kind: .manual, dataSource: .manual))
            try context.save()
        }

        let reopened = try factory.makeForProduction()
        let context = reopened.mainContext
        try ZapperToZerionMigrator.migrate(in: context)
        try ZapperToZerionMigrator.migrate(in: context)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let wallet = try #require(accounts.first { $0.id == walletID })
        let manual = try #require(accounts.first { $0.kind == .manual })
        #expect(wallet.dataSource == .zerion)
        #expect(wallet.addresses.map(\.address) == ["0xabc"])
        #expect(wallet.positions.map(\.id) == [positionID])
        #expect(wallet.positions.first?.tokens.first?.asset?.id == assetID)
        #expect(manual.dataSource == .manual)
    }

    @Test func `zapper wallet migration rolls back when saving fails`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let wallet = Account(name: "Legacy", kind: .wallet, dataSource: .zapper)
        context.insert(wallet)
        try context.save()

        #expect(throws: MigrationSaveError.forced) {
            try ZapperToZerionMigrator.migrate(in: context) { _ in
                throw MigrationSaveError.forced
            }
        }

        #expect(wallet.dataSource == .zapper)
    }

    @Test func `zapper wallet with unsupported cached holdings remains read only`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let supported = Position(positionType: .idle, chain: .ethereum)
        let unsupported = Position(positionType: .idle, chain: .mode)
        let wallet = Account(
            name: "Legacy mixed wallet",
            kind: .wallet,
            dataSource: .zapper,
            positions: [supported, unsupported])
        wallet.addresses = [WalletAddress(chain: nil, address: "0xabc", account: wallet)]
        context.insert(wallet)
        try context.save()

        try ZapperToZerionMigrator.migrate(in: context)

        #expect(wallet.dataSource == .zapper)
        #expect(Set(wallet.positions.compactMap(\.chain)) == [.ethereum, .mode])
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

private enum MigrationSaveError: Error {
    case forced
}
