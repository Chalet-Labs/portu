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

    @Test func `historical price id migration canonicalizes legacy rows and deduplicates`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let defaults = try migrationDefaults()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let canonicalID = "asset:base:0xabc"
        let olderCanonical = HistoricalPricePoint(
            coinGeckoId: canonicalID,
            day: day,
            price: 1,
            fetchedAt: day)
        let newerLegacy = HistoricalPricePoint(
            coinGeckoId: canonicalID,
            day: day,
            price: 2,
            fetchedAt: day.addingTimeInterval(60))
        newerLegacy.coinGeckoId = "zapper:base:0xabc"
        context.insert(olderCanonical)
        context.insert(newerLegacy)
        try context.save()

        try HistoricalPriceIDMigrator.migrate(in: context, defaults: defaults)
        try HistoricalPriceIDMigrator.migrate(in: context, defaults: defaults)

        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
        let survivor = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(survivor.id == newerLegacy.id)
        #expect(survivor.coinGeckoId == canonicalID)
        #expect(survivor.price == 2)
    }

    @Test func `historical price id migration deduplicates already canonical rows`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let defaults = try migrationDefaults()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let canonicalID = "asset:base:0xabc"
        let older = HistoricalPricePoint(
            coinGeckoId: canonicalID,
            day: day,
            price: 1,
            fetchedAt: day)
        let newer = HistoricalPricePoint(
            coinGeckoId: canonicalID,
            day: day,
            price: 2,
            fetchedAt: day.addingTimeInterval(60))
        context.insert(older)
        context.insert(newer)
        try context.save()

        try HistoricalPriceIDMigrator.migrate(in: context, defaults: defaults)

        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
        let survivor = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(survivor.id == newer.id)
        #expect(survivor.price == 2)
    }

    @Test func `completed historical price id migration skips subsequent cache fetches`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let defaults = try migrationDefaults()
        var fetchCount = 0

        try HistoricalPriceIDMigrator.migrate(
            in: context,
            defaults: defaults,
            fetch: { _ in
                fetchCount += 1
                return []
            })
        try HistoricalPriceIDMigrator.migrate(
            in: context,
            defaults: defaults,
            fetch: { _ in
                fetchCount += 1
                return []
            })

        #expect(fetchCount == 1)
    }

    @Test func `historical price id migration rolls back when saving fails`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let defaults = try migrationDefaults()
        let row = HistoricalPricePoint(
            coinGeckoId: "asset:base:0xabc",
            day: .now,
            price: 1)
        row.coinGeckoId = "zapper:base:0xabc"
        context.insert(row)
        try context.save()

        #expect(throws: MigrationSaveError.forced) {
            try HistoricalPriceIDMigrator.migrate(in: context, defaults: defaults) { _ in
                throw MigrationSaveError.forced
            }
        }

        let persisted = try #require(context.fetch(FetchDescriptor<HistoricalPricePoint>()).first)
        #expect(persisted.coinGeckoId == "zapper:base:0xabc")
        #expect(defaults.bool(forKey: HistoricalPriceIDMigrator.completionDefaultsKey) == false)
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

    @Test func `zapper Solana wallet with cached DeFi positions remains read only`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let staking = Position(positionType: .staking, chain: .solana)
        let wallet = Account(
            name: "Legacy Solana staking wallet",
            kind: .wallet,
            dataSource: .zapper,
            positions: [staking])
        wallet.addresses = [WalletAddress(chain: .solana, address: "SoLanaWallet", account: wallet)]
        context.insert(wallet)
        try context.save()

        try ZapperToZerionMigrator.migrate(in: context)

        #expect(wallet.dataSource == .zapper)
        #expect(wallet.positions.map(\.positionType) == [.staking])
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

    private func migrationDefaults() throws -> UserDefaults {
        let suiteName = "HistoricalPriceIDMigratorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private enum MigrationSaveError: Error {
    case forced
}
