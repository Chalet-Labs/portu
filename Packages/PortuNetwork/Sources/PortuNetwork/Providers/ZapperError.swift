import Foundation
import PortuCore

public enum ZapperError: Error, LocalizedError, Sendable {
    case invalidResponse
    case rateLimited
    case unauthorized
    case httpError(statusCode: Int)
    case decodingFailed
    case schemaChanged(context: String)
    case graphQLError(String)
    case unsupportedChain(Chain)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Zapper API"
        case .rateLimited:
            "Zapper API rate limit exceeded"
        case .unauthorized:
            "Invalid Zapper API key"
        case let .httpError(code):
            "Zapper API returned HTTP \(code)"
        case .decodingFailed:
            "Failed to parse Zapper API response"
        case let .schemaChanged(ctx):
            "Zapper API schema may have changed: \(ctx)"
        case let .graphQLError(message):
            "Zapper GraphQL error: \(message)"
        case let .unsupportedChain(chain):
            "Zapper does not support explicit chain filter: \(chain.rawValue)"
        }
    }
}
