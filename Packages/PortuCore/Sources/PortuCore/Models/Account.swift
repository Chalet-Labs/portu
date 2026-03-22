import Foundation
import SwiftData

@Model
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var exchangeType: ExchangeType?
    public var dataSource: DataSource

    @Relationship(deleteRule: .cascade, inverse: \WalletAddress.account)
    public var addresses: [WalletAddress]

    @Relationship(deleteRule: .cascade, inverse: \Position.account)
    public var positions: [Position]

    public var group: String?
    public var notes: String?
    public var lastSyncedAt: Date?

    /// nil = no error; set on failed sync, cleared on success
    public var lastSyncError: String?

    /// Inactive accounts are soft-hidden: excluded from sync, snapshots, and all views
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        exchangeType: ExchangeType? = nil,
        dataSource: DataSource,
        addresses: [WalletAddress] = [],
        positions: [Position] = [],
        group: String? = nil,
        notes: String? = nil,
        lastSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.exchangeType = exchangeType
        self.dataSource = dataSource
        self.addresses = addresses
        self.positions = positions
        self.group = group
        self.notes = notes
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncError = lastSyncError
        self.isActive = isActive
    }
}
