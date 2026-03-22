import Foundation
import Testing
import PortuCore
@testable import PortuNetwork

actor InMemorySecretStore: SecretStore {
    private var storage: [KeychainKey: String] = [:]

    func value(for key: KeychainKey) async throws(KeychainError) -> String? {
        storage[key]
    }

    func setValue(_ value: String, for key: KeychainKey) async throws(KeychainError) {
        storage[key] = value
    }

    func removeValue(for key: KeychainKey) async throws(KeychainError) {
        storage[key] = nil
    }
}

@Suite("Exchange Provider Tests")
struct ExchangeProviderTests {
    @Test func exchangeProviderRejectsMissingExchangeType() async {
        let provider = ExchangeProvider(secretStore: InMemorySecretStore())

        await #expect(throws: ExchangeProviderError.missingExchangeType) {
            _ = try await provider.fetchBalances(
                context: SyncContext(
                    accountId: UUID(),
                    kind: .exchange,
                    addresses: [],
                    exchangeType: nil
                )
            )
        }
    }
}
