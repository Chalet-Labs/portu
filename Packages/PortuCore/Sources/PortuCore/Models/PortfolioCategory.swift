import Foundation
import SwiftData

public enum PortfolioCategorySemanticRole: String, Codable, CaseIterable, Sendable {
    case normal
    case stablecoin
    case fiat
    case fallback
}

@Model
public final class PortfolioCategory {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var semanticRoleRawValue: String
    public var isSystemRequired: Bool

    public var semanticRole: PortfolioCategorySemanticRole {
        get {
            if let role = PortfolioCategorySemanticRole(rawValue: semanticRoleRawValue) {
                return role
            }
            assertionFailure("Unknown PortfolioCategorySemanticRole raw value: \(semanticRoleRawValue)")
            return .normal
        }
        set { semanticRoleRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        semanticRole: PortfolioCategorySemanticRole = .normal,
        isSystemRequired: Bool = false) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.semanticRoleRawValue = semanticRole.rawValue
        self.isSystemRequired = isSystemRequired
    }
}

public struct PortfolioCategorySnapshot: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let sortOrder: Int
    public let semanticRole: PortfolioCategorySemanticRole
    public let isSystemRequired: Bool

    public init(
        id: UUID,
        name: String,
        sortOrder: Int,
        semanticRole: PortfolioCategorySemanticRole,
        isSystemRequired: Bool) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.semanticRole = semanticRole
        self.isSystemRequired = isSystemRequired
    }

    public init(_ category: PortfolioCategory) {
        self.init(
            id: category.id,
            name: category.name,
            sortOrder: category.sortOrder,
            semanticRole: category.semanticRole,
            isSystemRequired: category.isSystemRequired)
    }

    public static func == (lhs: PortfolioCategorySnapshot, rhs: PortfolioCategorySnapshot) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
