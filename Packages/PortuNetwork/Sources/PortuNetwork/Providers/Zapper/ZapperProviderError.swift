import Foundation

public enum ZapperProviderError: Error, Sendable, Equatable {
    case invalidResponse(statusCode: Int)
    case decodingFailed
    case networkUnavailable
}
