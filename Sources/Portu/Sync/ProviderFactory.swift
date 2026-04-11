import Foundation
import PortuCore
import PortuNetwork

struct ProviderFactory {
    typealias Resolver = @Sendable (DataSource, SyncContext) throws -> any PortfolioDataProvider

    private let resolver: Resolver

    init(secretStore: any SecretStore, session: URLSession = .shared) {
        self.resolver = { dataSource, _ in
            switch dataSource {
            case .zapper:
                let apiKey: String
                do {
                    guard let key = try secretStore.get(key: .providerAPIKey(.zapper)) else {
                        throw SyncError.missingAPIKey("Zapper API key not configured")
                    }
                    apiKey = key
                } catch is KeychainError {
                    throw SyncError.missingAPIKey("Failed to read Zapper API key from Keychain")
                }
                return ZapperProvider(apiKey: apiKey, session: session)
            case .exchange:
                return ExchangeProvider(secretStore: secretStore, session: session)
            case .manual:
                fatalError("Manual accounts should not reach provider resolution")
            }
        }
    }

    /// Test-friendly init — inject a custom resolver or mock providers.
    init(resolver: @escaping Resolver) {
        self.resolver = resolver
    }

    func makeProvider(for dataSource: DataSource, context: SyncContext) throws -> any PortfolioDataProvider {
        try resolver(dataSource, context)
    }
}
