import Foundation

/// Single source of truth for whether an account is eligible for syncing.
/// Inactive accounts are soft-hidden and manual accounts have no data source,
/// so neither can be synced.
public enum AccountSyncEligibility {
    public static func isSyncable(isActive: Bool, dataSource: DataSource) -> Bool {
        isActive && dataSource != .manual
    }
}

public extension Account {
    /// Whether this account can be synced (active and not manual).
    var isSyncable: Bool {
        AccountSyncEligibility.isSyncable(isActive: isActive, dataSource: dataSource)
    }
}
