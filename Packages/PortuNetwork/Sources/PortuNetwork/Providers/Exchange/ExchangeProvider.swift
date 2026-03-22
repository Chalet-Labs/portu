import Foundation
import PortuCore

public actor ExchangeProvider: PortfolioDataProvider {
    public let capabilities = ProviderCapabilities(
        supportsTokenBalances: true,
        supportsDeFiPositions: false,
        supportsHealthFactors: false
    )

    private let secretStore: any SecretStore
    private let session: URLSession
    private let baseURL: URL

    public init(
        secretStore: any SecretStore,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.portu.app/exchange")!
    ) {
        self.secretStore = secretStore
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        guard let exchangeType = context.exchangeType else {
            throw ExchangeProviderError.missingExchangeType
        }

        guard let apiKey = try await secretStore.value(for: .exchangeAPIKey(context.accountId)), !apiKey.isEmpty else {
            throw ExchangeProviderError.missingAPIKey
        }
        guard let apiSecret = try await secretStore.value(for: .exchangeAPISecret(context.accountId)), !apiSecret.isEmpty else {
            throw ExchangeProviderError.missingAPISecret
        }

        var request = URLRequest(url: baseURL.appending(path: "balances/\(exchangeType.rawValue)"))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(apiSecret, forHTTPHeaderField: "X-API-Secret")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ExchangeProviderError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExchangeProviderError.invalidResponse(statusCode: 0)
        }
        guard httpResponse.statusCode == 200 else {
            throw ExchangeProviderError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        let decoded: ExchangeResponseDTO
        do {
            decoded = try JSONDecoder().decode(ExchangeResponseDTO.self, from: data)
        } catch {
            throw ExchangeProviderError.decodingFailed
        }

        return decoded.balances.map { balance in
            balance.positionDTO(sourceKeyPrefix: "\(exchangeType.rawValue):\(balance.symbol)")
        }
    }
}
