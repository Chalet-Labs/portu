import Foundation

public enum KeychainError: Error, Sendable {
    case decodingFailed
    case interactionNotAllowed
    case unexpectedStatus(OSStatus)
    case encodingFailed
}
