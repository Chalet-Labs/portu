import Foundation
import PortuCore
import PortuNetwork

enum ProviderFactoryError: Error, Sendable, Equatable {
    case unsupportedDataSource(DataSource)
}

struct ProviderFactory: Sendable {
    typealias Resolver = @Sendable (DataSource, SyncContext) throws -> any PortfolioDataProvider

    private let resolver: Resolver

    init(
        secretStore: any SecretStore = KeychainService(),
        session: URLSession = .shared
    ) {
        self.resolver = { dataSource, _ in
            switch dataSource {
            case .zapper:
                return ZapperProvider(session: session)
            case .exchange:
                return ExchangeProvider(secretStore: secretStore, session: session)
            case .manual:
                throw ProviderFactoryError.unsupportedDataSource(.manual)
            }
        }
    }

    init(resolver: @escaping Resolver) {
        self.resolver = resolver
    }

    init(
        zapperProvider: any PortfolioDataProvider,
        exchangeProvider: any PortfolioDataProvider
    ) {
        self.resolver = { dataSource, _ in
            switch dataSource {
            case .zapper:
                return zapperProvider
            case .exchange:
                return exchangeProvider
            case .manual:
                throw ProviderFactoryError.unsupportedDataSource(.manual)
            }
        }
    }

    func makeProvider(
        dataSource: DataSource,
        context: SyncContext
    ) throws -> any PortfolioDataProvider {
        try resolver(dataSource, context)
    }
}
