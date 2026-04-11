// Packages/PortuNetwork/Sources/PortuNetwork/Providers/ProviderCapabilities.swift
import Foundation

public struct ProviderCapabilities: Sendable {
    public let supportsTokenBalances: Bool
    public let supportsDeFiPositions: Bool
    public let supportsHealthFactors: Bool

    public init(
        supportsTokenBalances: Bool = true,
        supportsDeFiPositions: Bool = false,
        supportsHealthFactors: Bool = false) {
        self.supportsTokenBalances = supportsTokenBalances
        self.supportsDeFiPositions = supportsDeFiPositions
        self.supportsHealthFactors = supportsHealthFactors
    }
}
