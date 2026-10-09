import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Synchronization
import Testing

@MainActor
struct SyncEngineProgressTests {
    @Test func `full sync reports a step after each account and the last step after the snapshot`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let resolutions = Mutex(0)
        let failedAccountID = Mutex<UUID?>(nil)
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, syncContext in
                let resolution = resolutions.withLock { count in
                    count += 1
                    return count
                }
                guard resolution != 2 else {
                    failedAccountID.withLock { $0 = syncContext.accountId }
                    throw ProviderUnavailable()
                }
                return RecordingStubProvider(log: log)
            }))
        let accounts = ["First", "Second", "Third"].map { Account(name: $0, kind: .wallet, dataSource: .zerion) }
        accounts.forEach(context.insert)
        try context.save()

        let result = try await engine.sync(progress: recordProgress(into: log, container: container))

        // The second account fails when its provider is resolved, so no fetch sits between 1/4 and 2/4.
        #expect(log.events == [
            .fetch, .step(1, of: 4, savedSnapshots: 0),
            .step(2, of: 4, savedSnapshots: 0),
            .fetch, .step(3, of: 4, savedSnapshots: 0),
            .step(4, of: 4, savedSnapshots: 1)
        ])
        let failedName = try #require(accounts.first { $0.id == failedAccountID.withLock { $0 } }?.name)
        #expect(result.failedAccounts == [failedName])
    }

    @Test func `account sync reports its account step then the snapshot step`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in RecordingStubProvider(log: log) }))
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        context.insert(Account(name: "Other", kind: .wallet, dataSource: .zerion))
        try context.save()

        _ = try await engine.sync(accountID: account.id, progress: recordProgress(into: log, container: container))

        #expect(log.events == [
            .fetch, .step(1, of: 2, savedSnapshots: 0),
            .step(2, of: 2, savedSnapshots: 1)
        ])
    }

    @Test func `scope sync counts only the accounts in scope`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in RecordingStubProvider(log: log) }))
        context.insert(Account(name: "Wallet 1", kind: .wallet, dataSource: .zerion))
        context.insert(Account(name: "Wallet 2", kind: .wallet, dataSource: .zerion))
        context.insert(Account(name: "Kraken", kind: .exchange, exchangeType: .kraken, dataSource: .exchange))
        try context.save()

        _ = try await engine.sync(scope: .onchain, progress: recordProgress(into: log, container: container))

        #expect(log.events == [
            .fetch, .step(1, of: 3, savedSnapshots: 0),
            .fetch, .step(2, of: 3, savedSnapshots: 0),
            .step(3, of: 3, savedSnapshots: 1)
        ])
    }

    @Test func `manual only sync reports just the snapshot step`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in
                Issue.record("A manual-only sync must not resolve a provider")
                return RecordingStubProvider(log: log)
            }))
        context.insert(Account(name: "Manual", kind: .manual, dataSource: .manual))
        try context.save()

        _ = try await engine.sync(progress: recordProgress(into: log, container: container))

        #expect(log.events == [.step(1, of: 1, savedSnapshots: 1)])
    }

    @Test func `all accounts failing reports each account and no snapshot step`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in throw ProviderUnavailable() }))
        context.insert(Account(name: "Wallet 1", kind: .wallet, dataSource: .zerion))
        context.insert(Account(name: "Wallet 2", kind: .wallet, dataSource: .zerion))
        try context.save()

        await #expect(throws: SyncError.allAccountsFailed) {
            _ = try await engine.sync(progress: recordProgress(into: log, container: container))
        }

        #expect(log.events == [
            .step(1, of: 3, savedSnapshots: 0),
            .step(2, of: 3, savedSnapshots: 0)
        ])
    }

    @Test func `empty scope sync reports nothing`() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in RecordingStubProvider(log: log) }))
        context.insert(Account(name: "Kraken", kind: .exchange, exchangeType: .kraken, dataSource: .exchange))
        try context.save()

        _ = try await engine.sync(scope: .onchain, progress: recordProgress(into: log, container: container))

        #expect(log.events.isEmpty)
    }

    enum ClientEntryPoint: CaseIterable, Sendable {
        case full
        case scope
        case account
    }

    /// The live client is the seam that changes when the engine moves off the main actor, so
    /// pin that each of its entry points hands the reducer's handler through to the engine.
    @Test(arguments: ClientEntryPoint.allCases)
    func `live client passes progress through to the engine`(_ entryPoint: ClientEntryPoint) async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SyncEventLog()
        let engine = SyncEngine(
            modelContext: context,
            providerFactory: ProviderFactory(resolver: { _, _ in RecordingStubProvider(log: log) }))
        let account = Account(name: "Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        try context.save()
        let client = SyncEngineClient.live(engine: engine)
        let progress = recordProgress(into: log, container: container)

        switch entryPoint {
        case .full: _ = try await client.sync(progress)
        case .scope: _ = try await client.syncScope(.onchain, progress)
        case .account: _ = try await client.syncAccount(account.id, progress)
        }

        #expect(log.events == [
            .fetch, .step(1, of: 2, savedSnapshots: 0),
            .step(2, of: 2, savedSnapshots: 1)
        ])
    }

    /// Records each report together with the number of portfolio snapshots saved by then. The
    /// count goes through a second context, so rows the engine has inserted but not saved don't count.
    private func recordProgress(into log: SyncEventLog, container: ModelContainer) -> SyncProgressHandler {
        let observer = ModelContext(container)
        return { @MainActor progress in
            let savedSnapshots = try? observer.fetchCount(FetchDescriptor<PortfolioSnapshot>())
            log.append(.progress(progress, savedSnapshots: savedSnapshots))
        }
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
}

private enum SyncEvent: Equatable {
    case fetch
    case progress(SyncProgress, savedSnapshots: Int?)

    static func step(_ completed: Int, of total: Int, savedSnapshots: Int) -> Self {
        .progress(SyncProgress(completedSteps: completed, totalSteps: total), savedSnapshots: savedSnapshots)
    }
}

/// One ordered record of provider fetches and progress reports, so a spec pins when each
/// report happens relative to the work, not just which values arrive.
private final class SyncEventLog: Sendable {
    private let storage = Mutex<[SyncEvent]>([])

    var events: [SyncEvent] {
        storage.withLock { $0 }
    }

    func append(_ event: SyncEvent) {
        storage.withLock { $0.append(event) }
    }
}

private actor RecordingStubProvider: PortfolioDataProvider {
    nonisolated let capabilities = ProviderCapabilities()
    let log: SyncEventLog

    init(log: SyncEventLog) {
        self.log = log
    }

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        log.append(.fetch)
        return []
    }
}

private struct ProviderUnavailable: Error {}
