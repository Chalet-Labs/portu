import Foundation
import PortuCore

struct ZerionPnLEnvelope: Decodable {
    let data: ZerionPnLResource
    let meta: Meta?

    struct Meta: Decodable {
        let excludedFungibleIDs: [String]?
        let excludedFungibleImplementations: [String]?

        enum CodingKeys: String, CodingKey {
            case excludedFungibleIDs = "excluded_fungible_ids"
            case excludedFungibleImplementations = "excluded_fungible_implementations"
        }
    }
}

struct ZerionPnLResource: Decodable {
    let attributes: ZerionPnLMetrics
}

struct ZerionPnLMetrics: Decodable {
    let averageBuyPrice: Decimal?
    let averageSellPrice: Decimal?
    let totalGain: Decimal
    let realizedGain: Decimal?
    let unrealizedGain: Decimal?
    let relativeTotalGainPercentage: Decimal?
    let relativeRealizedGainPercentage: Decimal?
    let relativeUnrealizedGainPercentage: Decimal?
    let totalFee: Decimal?
    let totalInvested: Decimal?
    let realizedCostBasis: Decimal?
    let netInvested: Decimal?
    let receivedExternal: Decimal?
    let sentExternal: Decimal?
    let sentForNFTs: Decimal?
    let receivedForNFTs: Decimal?
    let breakdown: Breakdown?

    struct Breakdown: Decodable {
        let byImplementation: [String: ZerionPnLMetrics]?

        enum CodingKeys: String, CodingKey {
            case byImplementation = "by_implementation"
        }
    }

    enum CodingKeys: String, CodingKey {
        case averageBuyPrice = "average_buy_price"
        case averageSellPrice = "average_sell_price"
        case totalGain = "total_gain"
        case realizedGain = "realized_gain"
        case unrealizedGain = "unrealized_gain"
        case relativeTotalGainPercentage = "relative_total_gain_percentage"
        case relativeRealizedGainPercentage = "relative_realized_gain_percentage"
        case relativeUnrealizedGainPercentage = "relative_unrealized_gain_percentage"
        case totalFee = "total_fee"
        case totalInvested = "total_invested"
        case realizedCostBasis = "realized_cost_basis"
        case netInvested = "net_invested"
        case receivedExternal = "received_external"
        case sentExternal = "sent_external"
        case sentForNFTs = "sent_for_nfts"
        case receivedForNFTs = "received_for_nfts"
        case breakdown
    }
}

extension ProviderPnLRange {
    func zerionSinceMilliseconds(asOf date: Date) -> String? {
        guard self != .allTime else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let since: Date? = switch self {
        case .allTime:
            nil
        case .oneDay:
            calendar.date(byAdding: .day, value: -1, to: date)
        case .oneWeek:
            calendar.date(byAdding: .day, value: -7, to: date)
        case .oneMonth:
            calendar.date(byAdding: .month, value: -1, to: date)
        case .oneYear:
            calendar.date(byAdding: .year, value: -1, to: date)
        case .yearToDate:
            calendar.date(from: calendar.dateComponents([.year], from: date))
        }
        return since.map { String(Int64(($0.timeIntervalSince1970 * 1000).rounded())) }
    }
}
