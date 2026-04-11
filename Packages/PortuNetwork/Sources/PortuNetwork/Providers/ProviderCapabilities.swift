// Packages/PortuNetwork/Sources/PortuNetwork/Providers/ProviderCapabilities.swift
import Foundation

public struct ProviderCapabilities: Sendable {
    public var supportsTokenBalances: Bool
    public var supportsDeFiPositions: Bool
    public var supportsHealthFactors: Bool

    public init(
        supportsTokenBalances: Bool = true,
        supportsDeFiPositions: Bool = false,
        supportsHealthFactors: Bool = false) {
        self.supportsTokenBalances = supportsTokenBalances
        self.supportsDeFiPositions = supportsDeFiPositions
        self.supportsHealthFactors = supportsHealthFactors
    }
}
