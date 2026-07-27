// Packages/PortuNetwork/Sources/PortuNetwork/Providers/PortfolioDataProvider.swift
import Foundation
import PortuCore

/// Source-agnostic abstraction for portfolio data providers.
public protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchPositions(context: SyncContext) async throws -> [PositionDTO]
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

public extension PortfolioDataProvider {
    func fetchPositions(context: SyncContext) async throws -> [PositionDTO] {
        let balances = try await fetchBalances(context: context)
        let defi = try await fetchDeFiPositions(context: context)
        return balances + defi
    }

    /// Default: no DeFi support
    func fetchDeFiPositions(context _: SyncContext) async throws -> [PositionDTO] {
        []
    }
}
