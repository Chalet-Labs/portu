@testable import Portu
import PortuCore
import Testing

@MainActor
struct MigratingSecretStoreTests {
    @Test func `startup migration excludes retired Zapper credential`() {
        #expect(PortuApp.providerSecretMigrationKeys.contains(.providerAPIKey(.zerion)))
        #expect(!PortuApp.providerSecretMigrationKeys.contains(.providerAPIKey(.zapper)))
        #expect(PortuApp.retiredPlaintextSecretKeys == [.providerAPIKey(.zapper)])
    }

    @Test func `startup migration deletes retired Zapper plaintext without copying it`() async throws {
        let zapperKey = KeychainKey.providerAPIKey(.zapper)
        let zerionKey = KeychainKey.providerAPIKey(.zerion)
        let source = ThreadRecordingSecretStore(storage: [
            zapperKey.rawKey: "retired-zapper-key",
            zerionKey.rawKey: "zerion-key"
        ])
        let destination = ThreadRecordingSecretStore()
        let store = MigratingSecretStore(source: source, destination: destination)

        try await PortuApp.migrateSecrets(
            keys: [zerionKey],
            using: store)

        #expect(try source.get(key: zapperKey) == nil)
        #expect(try destination.get(key: zapperKey) == nil)
        #expect(try destination.get(key: zerionKey) == "zerion-key")
    }

    @Test func `startup secret migration runs off main through destination first fallback store`() async throws {
        let key = KeychainKey.providerAPIKey(.zerion)
        let source = ThreadRecordingSecretStore(storage: [key.rawKey: "legacy-zerion-key"])
        let destination = ThreadRecordingSecretStore()
        let store = MigratingSecretStore(source: source, destination: destination)

        #expect(try store.get(key: key) == "legacy-zerion-key")
        let preMigrationSourceReadCount = source.mainThreadFlags.count
        let preMigrationDestinationReadCount = destination.mainThreadFlags.count

        try await PortuApp.migrateSecrets(
            keys: [key],
            using: store)

        let migrationThreadFlags =
            Array(source.mainThreadFlags.dropFirst(preMigrationSourceReadCount))
                + Array(destination.mainThreadFlags.dropFirst(preMigrationDestinationReadCount))
        #expect(!migrationThreadFlags.isEmpty)
        #expect(migrationThreadFlags.allSatisfy { !$0 })
        #expect(try destination.get(key: key) == "legacy-zerion-key")
        #expect(try source.get(key: key) == nil)
    }

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
