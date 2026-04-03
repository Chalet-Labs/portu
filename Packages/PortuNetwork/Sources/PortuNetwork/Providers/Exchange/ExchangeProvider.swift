import Foundation
import PortuCore

public actor ExchangeProvider: PortfolioDataProvider {
    private let secretStore: any SecretStore
    private let session: URLSession

    nonisolated public var capabilities: ProviderCapabilities {
        ProviderCapabilities(supportsTokenBalances: true, supportsDeFiPositions: false, supportsHealthFactors: false)
    }

    public init(secretStore: any SecretStore, session: URLSession = .shared) {
        self.secretStore = secretStore
        self.session = session
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        guard let exchangeType = context.exchangeType else {
            throw ExchangeError.missingExchangeType
        }
        let keyPrefix = "portu.exchange.\(context.accountId.uuidString)"
        let apiKey: String
        let apiSecret: String
        do {
            guard
                let key = try secretStore.get(key: "\(keyPrefix).apiKey"),
                let secret = try secretStore.get(key: "\(keyPrefix).apiSecret")
            else {
                throw ExchangeError.missingCredentials
            }
            apiKey = key
            apiSecret = secret
        } catch is KeychainError {
            throw ExchangeError.missingCredentials
        }
        let passphrase = try? secretStore.get(key: "\(keyPrefix).passphrase")
        let client = resolveClient(for: exchangeType)
        let tokens = try await client.fetchBalances(apiKey: apiKey, apiSecret: apiSecret, passphrase: passphrase)
        return [PositionDTO(
            positionType: .idle, chain: nil,
            protocolId: nil, protocolName: exchangeType.rawValue.capitalized,
            protocolLogoURL: nil, healthFactor: nil, tokens: tokens)]
    }

    private func resolveClient(for type: ExchangeType) -> any ExchangeClient {
        switch type {
        case .kraken: KrakenClient(session: session)
        case .binance: BinanceClient(session: session)
        case .coinbase: CoinbaseClient(session: session)
        }
    }
}

enum ExchangeError: Error, LocalizedError {
    case missingExchangeType
    case missingCredentials
    case invalidCredentials
    case httpError
    case decodingFailed
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .missingExchangeType: "Account has no exchange type set"
        case .missingCredentials: "API credentials not found in Keychain"
        case .invalidCredentials: "Invalid API credentials"
        case .httpError: "Exchange API request failed"
        case .decodingFailed: "Failed to parse exchange API response"
        case let .notImplemented(name): "\(name) integration not yet implemented"
        }
    }
}
