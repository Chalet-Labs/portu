@testable import Portu
import PortuCore
import Testing

@MainActor
struct APIKeyNormalizationTests {
    @Test func `save trims API keys and updates bound values`() async throws {
        let store = InMemorySecretStore()
        let viewModel = APIKeysViewModel(secretStore: store)
        viewModel.zerionAPIKey = "  zerion-key \n"
        viewModel.debankAPIKey = "\tdebank-key "
        viewModel.coingeckoAPIKey = " coingecko-key\n"

        let succeeded = await viewModel.save()

        #expect(succeeded)
        #expect(viewModel.zerionAPIKey == "zerion-key")
        #expect(viewModel.debankAPIKey == "debank-key")
        #expect(viewModel.coingeckoAPIKey == "coingecko-key")
        #expect(try store.get(key: .providerAPIKey(.zerion)) == "zerion-key")
        #expect(try store.get(key: .serviceAPIKey("debank")) == "debank-key")
        #expect(try store.get(key: .serviceAPIKey("coingecko")) == "coingecko-key")
    }
}
