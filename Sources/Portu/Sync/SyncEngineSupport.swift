import Foundation
import PortuCore

/// Plain-value staging for syncAccount's build phase. Holding @Model instances
/// (Position/PositionToken) here would cause SwiftData to auto-register them
/// when their relationships are assigned to already-managed objects, defeating
/// the build-phase isolation. Pure structs keep the staging side-effect-free.
struct StagedPosition {
    let positionType: PositionType
    let chain: Chain?
    let protocolId: String?
    let protocolName: String?
    let protocolLogoURL: String?
    let healthFactor: Double?
    let netUSDValue: Decimal
    let tokens: [StagedToken]
}

struct StagedToken {
    let role: TokenRole
    let amount: Decimal
    let usdValue: Decimal
    /// Reference to the already-resolved managed asset. Storing a pointer in a
    /// value type does not trigger SwiftData tracking.
    let asset: Asset
}

struct AssetSnapshotAccumulator {
    var accountId: UUID
    var assetId: UUID
    var symbol: String
    var category: AssetCategory
    var grossAmount: Decimal = 0
    var grossUsdValue: Decimal = 0
    var borrowAmount: Decimal = 0
    var borrowUsdValue: Decimal = 0
}

enum SyncError: Error, LocalizedError, Equatable {
    case missingAPIKey(String)
    case noActiveAccounts
    case allAccountsFailed
    case accountNotFound
    case accountNotSyncable
    case accountInactive
    case unsupportedLegacyAccount

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(message): message
        case .noActiveAccounts: "No active accounts"
        case .allAccountsFailed: "All accounts failed to sync"
        case .accountNotFound: "Account not found"
        case .accountNotSyncable: "Account is not syncable"
        case .accountInactive: "Inactive accounts cannot be synced"
        case .unsupportedLegacyAccount:
            "Legacy Zapper accounts are read-only and cannot be synced; cached positions were preserved"
        }
    }
}
