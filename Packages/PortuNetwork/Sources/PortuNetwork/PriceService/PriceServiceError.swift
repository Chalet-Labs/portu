import Foundation

public enum PriceServiceError: Error, Sendable, Equatable {
    case rateLimited
    case networkUnavailable
    case decodingFailed
    case invalidResponse(statusCode: Int)
    case concurrentStreamNotSupported
}
