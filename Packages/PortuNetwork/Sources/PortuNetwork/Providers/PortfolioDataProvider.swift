// Packages/PortuNetwork/Sources/PortuNetwork/Providers/PortfolioDataProvider.swift
import Foundation
import PortuCore

/// Source-agnostic abstraction for portfolio data providers.
public protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

extension PortfolioDataProvider {
    /// Default: no DeFi support
    public func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] { [] }
}
