import Foundation
import PortuCore

public actor ZapperProvider: PortfolioDataProvider {
    public let capabilities = ProviderCapabilities(
        supportsTokenBalances: true,
        supportsDeFiPositions: true,
        supportsHealthFactors: true
    )

    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.zapper.xyz/v1")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchBalances(context: SyncContext) async throws -> [PositionDTO] {
        try await fetchPositions(path: "balances", context: context)
    }

    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        try await fetchPositions(path: "defi-positions", context: context)
    }

    private func fetchPositions(path: String, context: SyncContext) async throws -> [PositionDTO] {
        guard !context.addresses.isEmpty else {
            return []
        }

        var allPositions: [PositionDTO] = []

        for address in context.addresses {
            let requestURL = buildURL(path: path, address: address.address, chain: address.chain)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(from: requestURL)
            } catch {
                throw ZapperProviderError.networkUnavailable
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZapperProviderError.invalidResponse(statusCode: 0)
            }
            guard httpResponse.statusCode == 200 else {
                throw ZapperProviderError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            let decoded: ZapperResponseDTO
            do {
                decoded = try JSONDecoder().decode(ZapperResponseDTO.self, from: data)
            } catch {
                throw ZapperProviderError.decodingFailed
            }

            allPositions.append(contentsOf: decoded.positions.map(\.positionDTO))
        }

        return allPositions
    }

    private func buildURL(path: String, address: String, chain: Chain?) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "address", value: address)]
        if let chain {
            queryItems.append(URLQueryItem(name: "chain", value: chain.rawValue))
        }
        components?.queryItems = queryItems
        return components?.url ?? baseURL.appending(path: path)
    }
}
