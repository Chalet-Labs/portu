import Foundation

enum AccountSheetSaveError: Error, LocalizedError, Equatable {
    case missingEditedAccount
    case editedAccountMismatch
    case credentialSaveFailed(String)
    case accountSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEditedAccount:
            "The account being edited is no longer available."
        case .editedAccountMismatch:
            "The account being edited does not match the open sheet."
        case let .credentialSaveFailed(message):
            "Failed to save credentials: \(message)"
        case let .accountSaveFailed(message):
            "Failed to save account: \(message)"
        }
    }
}
