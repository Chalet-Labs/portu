import Foundation

public struct ZerionPortfolioSummary: Sendable, Equatable {
    public let totalPositions: Decimal
    public let positionsByChain: [String: Decimal]
    public let positionsByType: [String: Decimal]
    public let absoluteChange1D: Decimal?
    public let relativeChange1D: Decimal?
}

public struct ZerionPortfolioReconciliation: Sendable, Equatable {
    public let providerTotal: Decimal
    public let localTotal: Decimal
    public let absoluteDifference: Decimal
    public let relativeDifference: Decimal
    public let isWithinTolerance: Bool

    public static func compare(
        providerTotal: Decimal,
        localTotal: Decimal,
        absoluteTolerance: Decimal,
        relativeTolerance: Decimal) -> Self {
        let difference = absolute(providerTotal - localTotal)
        let denominator = max(absolute(providerTotal), absolute(localTotal))
        let relativeDifference = denominator == 0 ? 0 : difference / denominator
        return Self(
            providerTotal: providerTotal,
            localTotal: localTotal,
            absoluteDifference: difference,
            relativeDifference: relativeDifference,
            isWithinTolerance: difference <= max(0, absoluteTolerance)
                || relativeDifference <= max(0, relativeTolerance))
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}

struct ZerionPortfolioEnvelope: Decodable {
    let data: Resource

    struct Resource: Decodable {
        let attributes: Attributes
    }

    struct Attributes: Decodable {
        let positionsDistributionByType: [String: Decimal]
        let positionsDistributionByChain: [String: Decimal]
        let total: Total
        let changes: Changes?

        enum CodingKeys: String, CodingKey {
            case positionsDistributionByType = "positions_distribution_by_type"
            case positionsDistributionByChain = "positions_distribution_by_chain"
            case total
            case changes
        }
    }

    struct Total: Decodable {
        let positions: Decimal
    }

    struct Changes: Decodable {
        let absolute1D: Decimal?
        let percent1D: Decimal?

        enum CodingKeys: String, CodingKey {
            case absolute1D = "absolute_1d"
            case percent1D = "percent_1d"
        }
    }
}
