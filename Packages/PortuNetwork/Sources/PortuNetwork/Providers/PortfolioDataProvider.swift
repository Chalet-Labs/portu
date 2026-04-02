// Packages/PortuNetwork/Sources/PortuNetwork/Providers/PortfolioDataProvider.swift
import Foundation
import PortuCore

/// Source-agnostic abstraction for portfolio data providers.
public protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

public extension PortfolioDataProvider {
    /// Default: no DeFi support
    func fetchDeFiPositions(context _: SyncContext) async throws -> [PositionDTO] {
        []
    }
}
