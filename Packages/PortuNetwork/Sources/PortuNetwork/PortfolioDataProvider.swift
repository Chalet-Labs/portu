import Foundation
import PortuCore

/// Source-agnostic balance provider returning plain transport DTOs.
public protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

public extension PortfolioDataProvider {
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] {
        []
    }
}
