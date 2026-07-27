import Foundation
import PortuCore
import PortuNetwork

struct ProviderFactory {
    typealias Resolver = @Sendable (DataSource, SyncContext) throws -> any PortfolioDataProvider

    private let resolver: Resolver

    init(
        secretStore: any SecretStore,
        session: URLSession = .shared,
        zerionProvider: ZerionProvider? = nil) {
        let sharedZerionProvider = zerionProvider ?? ZerionProvider(client: ZerionAPIClient(
            apiKey: {
                try secretStore.get(key: .providerAPIKey(.zerion)) ?? ""
            },
            session: session))
        self.resolver = { dataSource, _ in
            switch dataSource {
            case .zapper:
                throw SyncError.unsupportedLegacyAccount
            case .zerion:
                guard
                    let apiKey = try secretStore.get(key: .providerAPIKey(.zerion)),
                    !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw SyncError.missingAPIKey("Zerion API key not configured")
                }
                return sharedZerionProvider
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
