import Foundation

public enum ExchangeProviderError: Error, Sendable, Equatable {
    case missingExchangeType
    case missingAPIKey
    case missingAPISecret
    case invalidResponse(statusCode: Int)
    case decodingFailed
    case networkUnavailable
}
