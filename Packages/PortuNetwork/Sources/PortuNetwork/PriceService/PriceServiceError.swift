import Foundation

public enum PriceServiceError: Error, Sendable {
    case rateLimited
    case networkUnavailable
    case decodingFailed
    case invalidResponse(statusCode: Int)
}
