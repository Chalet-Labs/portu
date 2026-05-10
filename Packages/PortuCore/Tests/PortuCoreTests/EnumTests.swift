import Foundation
@testable import PortuCore
import Testing

struct EnumTests {
    // MARK: - DataSource

    @Test func `data source cases`() {
        #expect(DataSource.allCases.count == 3)
        #expect(DataSource.allCases.contains(.zapper))
        #expect(DataSource.allCases.contains(.exchange))
        #expect(DataSource.allCases.contains(.manual))
    }

    @Test func `data source codable`() throws {
        let encoded = try JSONEncoder().encode(DataSource.zapper)
        let decoded = try JSONDecoder().decode(DataSource.self, from: encoded)
        #expect(decoded == .zapper)
    }

    // MARK: - PositionType

    @Test func `position type cases`() {
        #expect(PositionType.allCases.count == 7)
    }

    @Test func `position type codable`() throws {
        let encoded = try JSONEncoder().encode(PositionType.liquidityPool)
        let decoded = try JSONDecoder().decode(PositionType.self, from: encoded)
        #expect(decoded == .liquidityPool)
    }

    // MARK: - TokenRole

    @Test func `token role cases`() {
        #expect(TokenRole.allCases.count == 6)
    }

    @Test func `token role sign helpers`() {
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

    @Test func `token role codable`() throws {
        let encoded = try JSONEncoder().encode(TokenRole.lpToken)
        let decoded = try JSONDecoder().decode(TokenRole.self, from: encoded)
        #expect(decoded == .lpToken)
    }

    // MARK: - AssetCategory

    @Test func `asset category cases`() {
        #expect(AssetCategory.allCases.count == 8)
    }

    @Test func `asset category codable`() throws {
        let encoded = try JSONEncoder().encode(AssetCategory.stablecoin)
        let decoded = try JSONDecoder().decode(AssetCategory.self, from: encoded)
        #expect(decoded == .stablecoin)
    }

    // MARK: - Chain

    @Test func `chain cases`() {
        #expect(Chain.allCases.count == 28)
        #expect(Chain.allCases.contains(.gnosis))
        #expect(Chain.allCases.contains(.unichain))
        #expect(Chain.allCases.contains(.berachain))
        #expect(Chain.allCases.contains(.sonic))
        #expect(Chain.allCases.contains(.zksync))
        #expect(Chain.allCases.contains(.polygonZkEVM))
        #expect(Chain.allCases.contains(.moonbeam))
        #expect(Chain.allCases.contains(.ronin))
        #expect(Chain.allCases.contains(.mantle))
        #expect(Chain.allCases.contains(.immutableX))
        #expect(Chain.allCases.contains(.mode))
        #expect(Chain.allCases.contains(.linea))
        #expect(Chain.allCases.contains(.blast))
        #expect(Chain.allCases.contains(.taiko))
        #expect(Chain.allCases.contains(.scroll))
        #expect(Chain.allCases.contains(.hyperliquid))
        #expect(Chain.allCases.contains(.zora))
        #expect(Chain.allCases.contains(.monad))
        #expect(Chain.allCases.contains(.katana))
    }
}
