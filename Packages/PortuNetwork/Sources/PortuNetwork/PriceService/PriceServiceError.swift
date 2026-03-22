import Foundation

public enum PriceServiceError: Error, Sendable, Equatable {
    case invalidRequest
    case rateLimited
    case networkUnavailable
    case decodingFailed
    case invalidResponse(statusCode: Int)
}
