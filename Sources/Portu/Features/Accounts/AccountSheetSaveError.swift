import Foundation

enum AccountSheetSaveError: Error, LocalizedError, Equatable {
    case missingEditedAccount
    case editedAccountMismatch
    case legacyAccountReadOnly
    case unsupportedChain(String)
    case credentialSaveFailed(String)
    case accountSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEditedAccount:
            "The account being edited is no longer available."
        case .editedAccountMismatch:
            "The account being edited does not match the open sheet."
        case .legacyAccountReadOnly:
            "Legacy Zapper wallet identities are read-only. Add a new Zerion wallet to use a different address."
        case let .unsupportedChain(chain):
            "\(chain) is not supported by Zerion. Existing data remains available read-only."
        case let .credentialSaveFailed(message):
            "Failed to save credentials: \(message)"
        case let .accountSaveFailed(message):
            "Failed to save account: \(message)"
        }
    }
}
