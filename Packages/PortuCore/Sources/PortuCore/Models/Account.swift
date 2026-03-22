import Foundation
import SwiftData

/// The top-level persisted account entity for sync and manual entry.
@Model
public final class Account {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var exchangeType: ExchangeType?
    public var dataSource: DataSource
    public var group: String?
    public var notes: String?
    public var lastSyncedAt: Date?
    public var lastSyncError: String?
    public var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \WalletAddress.account)
    public var addresses: [WalletAddress]

    @Relationship(deleteRule: .cascade, inverse: \Position.account)
    public var positions: [Position]

    public init(
        name: String,
        kind: AccountKind,
        dataSource: DataSource,
        exchangeType: ExchangeType? = nil,
        group: String? = nil,
        notes: String? = nil,
        lastSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        isActive: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.exchangeType = exchangeType
        self.dataSource = dataSource
        self.group = group
        self.notes = notes
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncError = lastSyncError
        self.isActive = isActive
        self.addresses = []
        self.positions = []
    }
}
