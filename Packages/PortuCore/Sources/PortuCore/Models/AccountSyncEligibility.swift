import Foundation

/// Single source of truth for whether an account is eligible for syncing.
/// Inactive accounts are soft-hidden, manual accounts have no data source, and
/// retained legacy Zapper accounts are read-only.
public enum AccountSyncEligibility {
    public static func isSyncable(isActive: Bool, dataSource: DataSource) -> Bool {
        isActive && (dataSource == .zerion || dataSource == .exchange)
    }
}

public extension Account {
    /// Whether this account can be synced by a currently supported provider.
    var isSyncable: Bool {
        AccountSyncEligibility.isSyncable(isActive: isActive, dataSource: dataSource)
    }
}
