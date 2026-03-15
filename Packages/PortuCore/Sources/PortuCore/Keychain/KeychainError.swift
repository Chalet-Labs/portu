import Foundation

public enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}
