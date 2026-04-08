@testable import Portu
import PortuCore
import Testing

private final class MockSecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func get(key: String) throws(KeychainError) -> String? {
        storage[key]
    }

    func set(key: String, value: String) throws(KeychainError) {
        storage[key] = value
    }

    func delete(key: String) throws(KeychainError) {
        storage.removeValue(forKey: key)
    }
}

private final class FailingSecretStore: SecretStore, @unchecked Sendable {
    func get(key _: String) throws(KeychainError) -> String? {
        throw .unexpectedStatus(-25308) // errSecInteractionNotAllowed
    }

    func set(key _: String, value _: String) throws(KeychainError) {
        throw .unexpectedStatus(-25308)
    }

    func delete(key _: String) throws(KeychainError) {
        throw .unexpectedStatus(-25308)
    }
}

@MainActor
struct APIKeysViewModelTests {
    // MARK: - Initial State

    @Test func `initial state is empty`() {
        let vm = APIKeysViewModel(secretStore: MockSecretStore())

        #expect(vm.zapperAPIKey.isEmpty)
        #expect(vm.debankAPIKey.isEmpty)
        #expect(vm.coingeckoAPIKey.isEmpty)
        #expect(vm.rpcEndpoints.isEmpty)
    }

    // MARK: - Load

    @Test func `load populates fields from store`() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.provider.zapper.apiKey", value: "zap-123")
        try store.set(key: "portu.provider.debank.apiKey", value: "deb-456")
        try store.set(key: "portu.provider.coingecko.apiKey", value: "cg-789")

        let vm = APIKeysViewModel(secretStore: store)
        vm.load()

        #expect(vm.zapperAPIKey == "zap-123")
        #expect(vm.debankAPIKey == "deb-456")
        #expect(vm.coingeckoAPIKey == "cg-789")
    }

    @Test func `load populates RPC endpoints from store`() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.provider.rpc.ethereum", value: "https://eth.example.com")
        try store.set(key: "portu.provider.rpc.polygon", value: "https://poly.example.com")

        let vm = APIKeysViewModel(secretStore: store)
        vm.load()

        #expect(vm.rpcEndpoints[.ethereum] == "https://eth.example.com")
        #expect(vm.rpcEndpoints[.polygon] == "https://poly.example.com")
    }

    // MARK: - Save

    @Test func `save persists non empty API keys`() throws {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)

        vm.zapperAPIKey = "zap-abc"
        vm.debankAPIKey = "deb-def"
        vm.coingeckoAPIKey = "cg-ghi"
        vm.save()

        #expect(try store.get(key: "portu.provider.zapper.apiKey") == "zap-abc")
        #expect(try store.get(key: "portu.provider.debank.apiKey") == "deb-def")
        #expect(try store.get(key: "portu.provider.coingecko.apiKey") == "cg-ghi")
    }

    @Test func `save deletes keys when field cleared`() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.provider.zapper.apiKey", value: "old-key")

        let vm = APIKeysViewModel(secretStore: store)
        vm.load()
        vm.zapperAPIKey = ""
        vm.save()

        #expect(try store.get(key: "portu.provider.zapper.apiKey") == nil)
    }

    @Test func `save persists RPC endpoints`() throws {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)

        vm.addRPCEndpoint(chain: .arbitrum, url: "https://arb.example.com")
        vm.save()

        #expect(try store.get(key: "portu.provider.rpc.arbitrum") == "https://arb.example.com")
    }

    @Test func `save cleared RPC endpoint deletes from store`() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.provider.rpc.base", value: "https://base.example.com")

        let vm = APIKeysViewModel(secretStore: store)
        vm.load()
        vm.removeRPCEndpoint(chain: .base)
        vm.save()

        #expect(try store.get(key: "portu.provider.rpc.base") == nil)
    }

    // MARK: - Round-Trip

    @Test func `round trip save then load recovers same values`() {
        let store = MockSecretStore()

        let writer = APIKeysViewModel(secretStore: store)
        writer.zapperAPIKey = "zap-rt"
        writer.debankAPIKey = "deb-rt"
        writer.coingeckoAPIKey = "cg-rt"
        writer.addRPCEndpoint(chain: .optimism, url: "https://op.example.com")
        writer.save()

        let reader = APIKeysViewModel(secretStore: store)
        reader.load()

        #expect(reader.zapperAPIKey == "zap-rt")
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

    @Test func `load surfaces keychain error`() {
        let vm = APIKeysViewModel(secretStore: FailingSecretStore())
        vm.load()

        #expect(vm.keychainError != nil)
        #expect(vm.zapperAPIKey.isEmpty)
    }

    @Test func `save surfaces keychain error`() {
        let vm = APIKeysViewModel(secretStore: FailingSecretStore())
        vm.zapperAPIKey = "some-key"
        vm.save()

        #expect(vm.keychainError != nil)
    }

    @Test func `successful operations clear error`() {
        let store = MockSecretStore()
        let vm = APIKeysViewModel(secretStore: store)
        vm.keychainError = "stale error"

        vm.load()

        #expect(vm.keychainError == nil)
    }
}
