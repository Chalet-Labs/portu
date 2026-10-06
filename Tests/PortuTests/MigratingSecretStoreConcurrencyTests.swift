import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

/// The launch migration and the settings screens share one `MigratingSecretStore`, so each of
/// its operations must run to completion before another one starts touching the wrapped stores.
struct MigratingSecretStoreConcurrencyTests {
    /// Tracks how many store operations are inside the wrapped stores at the same moment.
    private final class OverlapMeter: Sendable {
        private struct Counts {
            var inFlight = 0
            var peak = 0
            var total = 0
        }

        private let counts = Mutex(Counts())

        var peak: Int {
            counts.withLock { $0.peak }
        }

        var total: Int {
            counts.withLock { $0.total }
        }

        /// Stays "inside" for a moment so a missing lock has time to be noticed.
        func occupy() {
            counts.withLock {
                $0.inFlight += 1
                $0.peak = max($0.peak, $0.inFlight)
                $0.total += 1
            }
            Thread.sleep(forTimeInterval: 0.0005)
            counts.withLock { $0.inFlight -= 1 }
        }
    }

    private final class MeteredSecretStore: SecretStore, Sendable {
        private let meter: OverlapMeter
        private let storage = Mutex<[KeychainKey: String]>([:])

        init(meter: OverlapMeter) {
            self.meter = meter
        }

        func get(key: KeychainKey) throws(KeychainError) -> String? {
            meter.occupy()
            return storage.withLock { $0[key] }
        }

        func set(key: KeychainKey, value: String) throws(KeychainError) {
            meter.occupy()
            storage.withLock { $0[key] = value }
        }

        func delete(key: KeychainKey) throws(KeychainError) {
            meter.occupy()
            storage.withLock { $0[key] = nil }
        }

        /// Direct access for the test itself, so it neither counts as an operation nor overlaps one.
        func seed(_ key: KeychainKey, _ value: String) {
            storage.withLock { $0[key] = value }
        }

        func peek(_ key: KeychainKey) -> String? {
            storage.withLock { $0[key] }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `concurrent operations never overlap inside the wrapped stores`() async {
        let meter = OverlapMeter()
        let source = MeteredSecretStore(meter: meter)
        let destination = MeteredSecretStore(meter: meter)
        let store = MigratingSecretStore(source: source, destination: destination)
        let workers = 8
        let rounds = 15

        let failures = await DeadlockWatchdog.guarding("migrating store contention") {
            Self.hammer(store, source: source, workers: workers, rounds: rounds)
        }

        #expect(failures == [])
        #expect(meter.peak == 1)
        #expect(meter.total > workers * rounds)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a failing operation releases the lock for other threads`() {
        let key = KeychainKey.providerAPIKey(.zerion)
        let destination = InMemorySecretStore()
        destination.throwOnSet = true
        let store = MigratingSecretStore(source: InMemorySecretStore(), destination: destination)

        var failed = false
        do {
            try store.set(key: key, value: "new-value")
        } catch {
            failed = true
        }
        #expect(failed)

        // A recursive lock would let this same thread back in even if the lock leaked,
        // so the follow-up has to come from a different thread.
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? store.get(key: key)
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + .seconds(5)) == .success)
    }

    // MARK: - Helpers

    /// Each worker owns its keys, so only the lock decides whether operations interleave.
    private static func hammer(
        _ store: MigratingSecretStore,
        source: MeteredSecretStore,
        workers: Int,
        rounds: Int) -> [String] {
        let failures = ConcurrentFailureLog()
        let workerIDs = (0 ..< workers).map { _ in UUID() }

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let legacy = KeychainKey.exchangeAPIKey(workerIDs[worker])
            let retired = KeychainKey.exchangeAPISecret(workerIDs[worker])
            for round in 0 ..< rounds {
                let label = "worker \(worker) round \(round)"
                do {
                    source.seed(legacy, "legacy-\(round)")
                    source.seed(retired, "retired-\(round)")
                    try store.migrate(keys: [legacy], retiredKeys: [retired])
                    failures.check(source.peek(legacy) == nil, "\(label): legacy value left in source")
                    failures.check(source.peek(retired) == nil, "\(label): retired value left in source")
                    try failures.check(store.get(key: legacy) == "legacy-\(round)", "\(label): migrated value")
                    try failures.check(store.get(key: retired) == nil, "\(label): retired value was copied")

                    try store.set(key: legacy, value: "new-\(round)")
                    try failures.check(store.get(key: legacy) == "new-\(round)", "\(label): written value")

                    try store.delete(key: legacy)
                    try failures.check(store.get(key: legacy) == nil, "\(label): deleted value")
                } catch {
                    failures.record("\(label): threw \(error)")
                }
            }
        }
        return failures.all
    }
}
