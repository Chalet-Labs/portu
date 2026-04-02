import Foundation
import PortuCore
@testable import PortuNetwork

actor MockProvider: PortfolioDataProvider {
    var balancesToReturn: [PositionDTO] = []
    var defiToReturn: [PositionDTO] = []
    var shouldThrow: Error?
    var fetchBalancesCalled = false
    var fetchDeFiCalled = false

    nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities(supportsTokenBalances: true, supportsDeFiPositions: true, supportsHealthFactors: false)
    }

    func configure(balances: [PositionDTO], defi: [PositionDTO] = [], error: Error? = nil) {
        balancesToReturn = balances
        defiToReturn = defi
        shouldThrow = error
    }

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        fetchBalancesCalled = true
        if let error = shouldThrow { throw error }
        return balancesToReturn
    }

    func fetchDeFiPositions(context _: SyncContext) async throws -> [PositionDTO] {
        fetchDeFiCalled = true
        if let error = shouldThrow { throw error }
        return defiToReturn
    }
}
