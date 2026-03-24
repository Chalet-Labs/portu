import Foundation
import PortuCore

@MainActor
@Observable
final class ExposureViewModel {
    var displayMode: ExposureDisplayMode = .category

    let positions: [Position]

    private let projectedCategoryRows: [ExposureRow]
    private let projectedAssetRows: [ExposureRow]

    var categoryRows: [ExposureRow] {
        projectedCategoryRows
    }

    var assetRows: [ExposureRow] {
        projectedAssetRows
    }

    var netExposureExcludingStablecoins: Decimal {
        categoryRows.reduce(.zero) { partialResult, row in
            partialResult + row.netExposure
        }
    }

    init(
        positions: [Position] = []
    ) {
        let activePositions = positions.filter { $0.account?.isActive == true }

        self.positions = activePositions
        projectedCategoryRows = Self.makeCategoryRows(positions: activePositions)
        projectedAssetRows = Self.makeAssetRows(positions: activePositions)
    }

    private struct ExposureAggregate {
        let id: String
        let name: String
        var assetID: UUID?
        let assetSymbol: String?
        let category: AssetCategory?
        var spotAssets: Decimal = .zero
        var liabilities: Decimal = .zero
        var derivativesLong: Decimal = .zero
        var derivativesShort: Decimal = .zero
    }

    private static func makeCategoryRows(
        positions: [Position]
    ) -> [ExposureRow] {
        let aggregates = positions.reduce(into: [AssetCategory: ExposureAggregate]()) { partialResult, position in
            for token in position.tokens where token.role != .reward {
                let category = token.asset?.category ?? .other
                var aggregate = partialResult[category] ?? ExposureAggregate(
                    id: "category:\(category.rawValue)",
                    name: categoryTitle(for: category),
                    assetID: nil,
                    assetSymbol: nil,
                    category: category
                )

                updateAggregate(&aggregate, with: token)
                partialResult[category] = aggregate
            }
        }

        return aggregates.values
            .map(makeRow)
            .sorted(by: compareRows)
    }

    private static func makeAssetRows(
        positions: [Position]
    ) -> [ExposureRow] {
        let aggregates = positions.reduce(into: [String: ExposureAggregate]()) { partialResult, position in
            for token in position.tokens where token.role != .reward {
                let key = makeAssetKey(for: token)
                let asset = token.asset
                let category = asset?.category ?? .other
                var aggregate = partialResult[key] ?? ExposureAggregate(
                    id: key,
                    name: asset?.name ?? asset?.symbol ?? "Unknown Asset",
                    assetID: asset?.id,
                    assetSymbol: asset?.symbol ?? "Unknown",
                    category: category
                )

                aggregate.assetID = aggregate.assetID ?? asset?.id
                updateAggregate(&aggregate, with: token)
                partialResult[key] = aggregate
            }
        }

        return aggregates.values
            .map(makeRow)
            .sorted(by: compareRows)
    }

    private static func updateAggregate(
        _ aggregate: inout ExposureAggregate,
        with token: PositionToken
    ) {
        switch token.role {
        case .borrow:
            aggregate.liabilities += token.usdValue
        case .balance, .supply, .stake, .lpToken:
            aggregate.spotAssets += token.usdValue
        case .reward:
            break
        }
    }

    private static func makeRow(
        from aggregate: ExposureAggregate
    ) -> ExposureRow {
        ExposureRow(
            id: aggregate.id,
            name: aggregate.name,
            assetID: aggregate.assetID,
            assetSymbol: aggregate.assetSymbol,
            category: aggregate.category,
            spotAssets: aggregate.spotAssets,
            liabilities: aggregate.liabilities,
            derivativesLong: aggregate.derivativesLong,
            derivativesShort: aggregate.derivativesShort
        )
    }

    private static func makeAssetKey(
        for token: PositionToken
    ) -> String {
        if let coinGeckoID = token.asset?.coinGeckoId {
            return "cg:\(coinGeckoID)"
        }
        if let assetID = token.asset?.id {
            return "asset:\(assetID.uuidString)"
        }

        return "token:\(token.id.uuidString)"
    }

    private static func categoryTitle(
        for category: AssetCategory
    ) -> String {
        switch category {
        case .defi:
            "DeFi"
        case .stablecoin:
            "Stablecoin"
        default:
            category.rawValue.capitalized
        }
    }

    private static func compareRows(
        _ lhs: ExposureRow,
        _ rhs: ExposureRow
    ) -> Bool {
        if lhs.netExposure == rhs.netExposure {
            if lhs.spotNet == rhs.spotNet {
                return lhs.name < rhs.name
            }

            return lhs.spotNet > rhs.spotNet
        }

        return lhs.netExposure > rhs.netExposure
    }
}
