@testable import Portu
import PortuCore
import Testing

struct MigratingSecretStoreTests {
    @Test func `falls back to retained source when destination read fails`() throws {
        let key = KeychainKey.providerAPIKey(.zerion)
        let source = InMemorySecretStore()
        source.storage[key] = "legacy-zerion-key"
        let destination = InMemorySecretStore()
        destination.throwOnGet = true
        let store = MigratingSecretStore(source: source, destination: destination)

        #expect(try store.get(key: key) == "legacy-zerion-key")
    }
}
