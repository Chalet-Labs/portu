import Foundation

public enum ZerionError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey
    case untrustedURL
    case invalidResponse
    case badRequest
    case apiError(statusCode: Int, title: String?, detail: String?)
    case unauthorized
    case paymentRequired
    case notFound
    case rateLimited(remainingSecond: Int?, remainingDay: Int?, remainingMonth: Int?, reset: String?)
    case temporarilyUnavailable(retryAfter: Int?)
    case httpError(statusCode: Int)
    case decodingFailed
    case unsupportedChain(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Zerion API key not configured"
        case .untrustedURL:
            "Zerion returned an untrusted URL"
        case .invalidResponse:
            "Zerion returned an invalid response"
        case .badRequest:
            "Zerion rejected the request"
        case let .apiError(statusCode, title, detail):
            [title, detail]
                .compactMap(\.self)
                .first ?? "Zerion HTTP error \(statusCode)"
        case .unauthorized:
            "Zerion API key is invalid"
        case .paymentRequired:
            "Zerion API plan does not permit this request"
        case .notFound:
            "Zerion resource was not found"
        case .rateLimited:
            "Zerion request limit reached"
        case .temporarilyUnavailable:
            "Zerion data is temporarily unavailable"
        case let .httpError(statusCode):
            "Zerion HTTP error \(statusCode)"
        case .decodingFailed:
            "Zerion response format was not recognized"
        case let .unsupportedChain(chain):
            "Zerion does not support \(chain)"
        case let .invalidData(context):
            "Invalid Zerion data: \(context)"
        }
    }
}
