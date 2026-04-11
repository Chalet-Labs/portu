import Foundation

public enum KeychainError: Error, Sendable, LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case interactionNotAllowed

    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status): "Keychain error: \(status)"
        case .encodingFailed: "Failed to encode/decode keychain data"
        case .interactionNotAllowed: "Keychain interaction not allowed (device may be locked)"
        }
    }
}
