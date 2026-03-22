import Foundation

/// Declares which optional data a provider can supply.
public struct ProviderCapabilities: Sendable {
    public let supportsTokenBalances: Bool
    public let supportsDeFiPositions: Bool
    public let supportsHealthFactors: Bool

    public init(
        supportsTokenBalances: Bool = true,
        supportsDeFiPositions: Bool,
        supportsHealthFactors: Bool
    ) {
        self.supportsTokenBalances = supportsTokenBalances
        self.supportsDeFiPositions = supportsDeFiPositions
        self.supportsHealthFactors = supportsHealthFactors
    }
}
