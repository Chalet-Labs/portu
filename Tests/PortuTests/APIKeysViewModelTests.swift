import Foundation
@testable import Portu
import PortuCore
import Testing

private final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func get(key: KeychainKey) throws(KeychainError) -> String? {
        storage[key.rawKey]
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        storage[key.rawKey] = value
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        storage.removeValue(forKey: key.rawKey)
    }
}

private final class FailingSecretStore: SecretStore, @unchecked Sendable {
    func get(key _: KeychainKey) throws(KeychainError) -> String? {
        throw .unexpectedStatus(-25308) // errSecInteractionNotAllowed
    }

    func set(key _: KeychainKey, value _: String) throws(KeychainError) {
        throw .unexpectedStatus(-25308)
    }

    func delete(key _: KeychainKey) throws(KeychainError) {
        throw .unexpectedStatus(-25308)
    }
}

private final class ThreadRecordingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]
    private var recordedMainThreadFlags: [Bool] = []
    private var recordedDeletedKeys: [KeychainKey] = []

    init(storage: [String: String] = [:]) {
        self.storage = storage
    }

    var mainThreadFlags: [Bool] {
        lock.withLock { recordedMainThreadFlags }
    }

    var deletedKeys: [KeychainKey] {
        lock.withLock { recordedDeletedKeys }
    }

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        lock.withLock {
            recordedMainThreadFlags.append(Thread.isMainThread)
            return storage[key.rawKey]
        }
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        lock.withLock {
            recordedMainThreadFlags.append(Thread.isMainThread)
            storage[key.rawKey] = value
        }
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        lock.withLock {
            recordedMainThreadFlags.append(Thread.isMainThread)
            recordedDeletedKeys.append(key)
            storage.removeValue(forKey: key.rawKey)
        }
    }
}

@MainActor
struct APIKeysViewModelTests {
    @Test
    func `host uses an isolated keychain service`() {
        #expect(PortuApp.secretStoreService(
            environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"],
            bundleIdentifier: "com.portu.app") == "com.portu.app.tests")
        #expect(PortuApp.secretStoreService(
            environment: [:],
            bundleIdentifier: "com.portu.app") == "com.portu.app")
    }

    @Test func `default secret store factory uses the isolated test service`() {
        var capturedService: String?

        _ = PortuApp.makeSecretStore(
            environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"],
            bundleIdentifier: "com.portu.app") { service in
                capturedService = service
                return MockSecretStore()
            }

        #expect(capturedService == "com.portu.app.tests")
    }

    @Test func `view model keychain access runs off the main actor`() async {
        let store = ThreadRecordingSecretStore(storage: [
            KeychainKey.providerAPIKey(.zerion).rawKey: "zerion-key"
        ])
        let viewModel = APIKeysViewModel(secretStore: store)

        await viewModel.load()
        viewModel.zerionAPIKey = "updated-key"
        await viewModel.save()

        #expect(store.mainThreadFlags.isEmpty == false)
        #expect(store.mainThreadFlags.allSatisfy { $0 == false })
    }

    @Test func `saving an API key does not delete RPC keys that were already absent`() async {
        let store = ThreadRecordingSecretStore()
        let viewModel = APIKeysViewModel(secretStore: store)
        await viewModel.load()
        viewModel.zerionAPIKey = "zerion-key"

        await viewModel.save()

        #expect(store.deletedKeys.contains { key in
            if case .rpcEndpoint = key { true } else { false }
        } == false)
    }

    @Test func `startup migration excludes retired Zapper credential`() {
        #expect(PortuApp.providerSecretMigrationKeys.contains(.providerAPIKey(.zerion)))
        #expect(!PortuApp.providerSecretMigrationKeys.contains(.providerAPIKey(.zapper)))
    }

    @Test func `startup secret migration completes off main before dependencies read keys`() throws {
        let key = KeychainKey.providerAPIKey(.zerion)
        let source = ThreadRecordingSecretStore(storage: [key.rawKey: "legacy-zerion-key"])
        let destination = ThreadRecordingSecretStore()

        try PortuApp.migrateSecretsBeforeDependencyConstruction(
            keys: [key],
            from: source,
            to: destination)

        let migrationThreadFlags = source.mainThreadFlags + destination.mainThreadFlags
        #expect(!migrationThreadFlags.isEmpty)
        #expect(migrationThreadFlags.allSatisfy { !$0 })
        #expect(try destination.get(key: key) == "legacy-zerion-key")
        #expect(try source.get(key: key) == nil)
    }

    // MARK: - Initial State

    @Test func `initial state is empty`() {
        let vm = APIKeysViewModel(secretStore: MockSecretStore())

        #expect(vm.zerionAPIKey.isEmpty)
        #expect(vm.debankAPIKey.isEmpty)
        #expect(vm.coingeckoAPIKey.isEmpty)
        #expect(vm.rpcEndpoints.isEmpty)
    }

    // MARK: - Load

    @Test func `load populates fields from store`() async throws {
        let store = MockSecretStore()
        try store.set(key: .providerAPIKey(.zerion), value: "zap-123")
        try store.set(key: .serviceAPIKey("debank"), value: "deb-456")
        try store.set(key: .serviceAPIKey("coingecko"), value: "cg-789")

        let vm = APIKeysViewModel(secretStore: store)
        await vm.load()

        #expect(vm.zerionAPIKey == "zap-123")
        #expect(vm.debankAPIKey == "deb-456")
        #expect(vm.coingeckoAPIKey == "cg-789")
    }

    @Test func `load populates RPC endpoints from store`() async throws {
        let store = MockSecretStore()
        try store.set(key: .rpcEndpoint(.ethereum), value: "https://eth.example.com")
        try store.set(key: .rpcEndpoint(.polygon), value: "https://poly.example.com")

        let vm = APIKeysViewModel(secretStore: store)
        await vm.load()

        #expect(vm.rpcEndpoints[.ethereum] == "https://eth.example.com")
        #expect(vm.rpcEndpoints[.polygon] == "https://poly.example.com")
    }

    // MARK: - Save

    @Test func `save persists non empty API keys`() async throws {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)

        vm.zerionAPIKey = "zap-abc"
        vm.debankAPIKey = "deb-def"
        vm.coingeckoAPIKey = "cg-ghi"
        await vm.save()

        #expect(try store.get(key: .providerAPIKey(.zerion)) == "zap-abc")
        #expect(try store.get(key: .serviceAPIKey("debank")) == "deb-def")
        #expect(try store.get(key: .serviceAPIKey("coingecko")) == "cg-ghi")
    }

    @Test func `historical backfill reads zerion key saved by settings`() async throws {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)
        vm.zerionAPIKey = "zap-backfill"
        await vm.save()

        #expect(try PortuApp.zerionAPIKey(from: store) == "zap-backfill")
    }

    @Test func `locked keychain is not interpreted as a missing Zerion key`() {
        #expect(throws: KeychainError.unexpectedStatus(-25308)) {
            _ = try PortuApp.zerionAPIKey(from: FailingSecretStore())
        }
    }

    @Test func `save deletes keys when field cleared`() async throws {
        let store = MockSecretStore()
        try store.set(key: .providerAPIKey(.zerion), value: "old-key")

        let vm = APIKeysViewModel(secretStore: store)
        await vm.load()
        vm.zerionAPIKey = ""
        await vm.save()

        #expect(try store.get(key: .providerAPIKey(.zerion)) == nil)
    }

    @Test func `save persists RPC endpoints`() async throws {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)

        vm.addRPCEndpoint(chain: .arbitrum, url: "https://arb.example.com")
        await vm.save()

        #expect(try store.get(key: .rpcEndpoint(.arbitrum)) == "https://arb.example.com")
    }

    @Test func `save cleared RPC endpoint deletes from store`() async throws {
        let store = MockSecretStore()
        try store.set(key: .rpcEndpoint(.base), value: "https://base.example.com")

        let vm = APIKeysViewModel(secretStore: store)
        await vm.load()
        vm.removeRPCEndpoint(chain: .base)
        await vm.save()

        #expect(try store.get(key: .rpcEndpoint(.base)) == nil)
    }

    // MARK: - Round-Trip

    @Test func `round trip save then load recovers same values`() async {
        let store = MockSecretStore()

        let writer = APIKeysViewModel(secretStore: store)
        writer.zerionAPIKey = "zap-rt"
        writer.debankAPIKey = "deb-rt"
        writer.coingeckoAPIKey = "cg-rt"
        writer.addRPCEndpoint(chain: .optimism, url: "https://op.example.com")
        await writer.save()

        let reader = APIKeysViewModel(secretStore: store)
        await reader.load()

        #expect(reader.zerionAPIKey == "zap-rt")
        #expect(reader.debankAPIKey == "deb-rt")
        #expect(reader.coingeckoAPIKey == "cg-rt")
        #expect(reader.rpcEndpoints[.optimism] == "https://op.example.com")
    }

    // MARK: - RPC Endpoint Mutations

    @Test func `add RPC endpoint adds to dictionary`() {
        let vm = APIKeysViewModel(secretStore: MockSecretStore())

        vm.addRPCEndpoint(chain: .ethereum, url: "https://eth.example.com")

        #expect(vm.rpcEndpoints[.ethereum] == "https://eth.example.com")
    }

    @Test func `remove RPC endpoint removes from dictionary`() {
        let vm = APIKeysViewModel(secretStore: MockSecretStore())

        vm.addRPCEndpoint(chain: .solana, url: "https://sol.example.com")
        vm.removeRPCEndpoint(chain: .solana)

        #expect(vm.rpcEndpoints[.solana] == nil)
    }

    // MARK: - Error Handling

    @Test func `load surfaces actionable keychain error`() async {
        let vm = APIKeysViewModel(secretStore: FailingSecretStore())
        await vm.load()

        #expect(vm.secretStoreError == "Unable to access API keys in Keychain. Unlock your Mac and try again.")
        #expect(vm.zerionAPIKey.isEmpty)
    }

    @Test func `save surfaces actionable keychain error`() async {
        let vm = APIKeysViewModel(secretStore: FailingSecretStore())
        vm.zerionAPIKey = "some-key"
        await vm.save()

        #expect(vm.secretStoreError == "Unable to save API keys in Keychain. Unlock your Mac and try again.")
    }

    @Test func `successful operations clear error`() async {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)
        vm.secretStoreError = "stale error"

        await vm.load()

        #expect(vm.secretStoreError == nil)
    }
}
