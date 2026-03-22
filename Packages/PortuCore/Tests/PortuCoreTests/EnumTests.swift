import Testing
import Foundation
@testable import PortuCore

@Suite("Enum Tests")
struct EnumTests {

    // MARK: - DataSource

    @Test func dataSourceCases() {
        #expect(DataSource.allCases.count == 3)
        #expect(DataSource.allCases.contains(.zapper))
        #expect(DataSource.allCases.contains(.exchange))
        #expect(DataSource.allCases.contains(.manual))
    }

    @Test func dataSourceCodable() throws {
        let encoded = try JSONEncoder().encode(DataSource.zapper)
        let decoded = try JSONDecoder().decode(DataSource.self, from: encoded)
        #expect(decoded == .zapper)
    }

    // MARK: - PositionType

    @Test func positionTypeCases() {
        #expect(PositionType.allCases.count == 7)
    }

    @Test func positionTypeCodable() throws {
        let encoded = try JSONEncoder().encode(PositionType.liquidityPool)
        let decoded = try JSONDecoder().decode(PositionType.self, from: encoded)
        #expect(decoded == .liquidityPool)
    }

    // MARK: - TokenRole

    @Test func tokenRoleCases() {
        #expect(TokenRole.allCases.count == 6)
    }

    @Test func tokenRoleSignHelpers() {
        // Positive roles
        #expect(TokenRole.supply.isPositive)
        #expect(TokenRole.balance.isPositive)
        #expect(TokenRole.stake.isPositive)
        #expect(TokenRole.lpToken.isPositive)

        // Borrow
        #expect(TokenRole.borrow.isBorrow)
        #expect(!TokenRole.borrow.isPositive)
        #expect(!TokenRole.borrow.isReward)

        // Reward
        #expect(TokenRole.reward.isReward)
        #expect(!TokenRole.reward.isPositive)
        #expect(!TokenRole.reward.isBorrow)
    }

    @Test func tokenRoleCodable() throws {
        let encoded = try JSONEncoder().encode(TokenRole.lpToken)
        let decoded = try JSONDecoder().decode(TokenRole.self, from: encoded)
        #expect(decoded == .lpToken)
    }

    // MARK: - AssetCategory

    @Test func assetCategoryCases() {
        #expect(AssetCategory.allCases.count == 8)
    }

    @Test func assetCategoryCodable() throws {
        let encoded = try JSONEncoder().encode(AssetCategory.stablecoin)
        let decoded = try JSONDecoder().decode(AssetCategory.self, from: encoded)
        #expect(decoded == .stablecoin)
    }

    // MARK: - Chain

    @Test func chainCases() {
        #expect(Chain.allCases.count == 11)
        #expect(Chain.allCases.contains(.monad))
        #expect(Chain.allCases.contains(.katana))
    }
}
