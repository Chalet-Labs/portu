import Foundation
import PortuCore

@MainActor
@Observable
final class AllAssetsViewModel {
    var selectedTab: AllAssetsTab = .assets
    var searchText = ""
    var grouping: AllAssetsGrouping = .category

    let positions: [Position]
    let livePrices: [String: Decimal]

    private let projectedAssetRows: [AssetTableRow]
    private let projectedPlatformRows: [PlatformTableRow]
    private let projectedNetworkRows: [NetworkTableRow]

    var assetRows: [AssetTableRow] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard query.isEmpty == false else {
            return projectedAssetRows
        }

        return projectedAssetRows.filter { row in
            row.searchIndex.contains(query)
        }
    }

    var platformRows: [PlatformTableRow] {
        projectedPlatformRows
    }

    var networkRows: [NetworkTableRow] {
        projectedNetworkRows
    }

    init(
        positions: [Position],
        livePrices: [String: Decimal]
    ) {
        let activePositions = positions.filter { $0.account?.isActive == true }

        self.positions = activePositions
        self.livePrices = livePrices
        projectedAssetRows = Self.makeAssetRows(
            positions: activePositions,
            livePrices: livePrices
        )
        projectedPlatformRows = Self.makePlatformRows(positions: activePositions)
        projectedNetworkRows = Self.makeNetworkRows(positions: activePositions)
    }

    private struct AssetAggregate {
        let id: String
        let assetID: UUID?
        let symbol: String
        let name: String
        let category: AssetCategory
        let coinGeckoID: String?
        var positiveAmount: Decimal = .zero
        var borrowAmount: Decimal = .zero
        var positiveSyncValue: Decimal = .zero
        var borrowSyncValue: Decimal = .zero
        var accountGroups = Set<String>()

        var netAmount: Decimal {
            positiveAmount - borrowAmount
        }
    }

    private struct PlatformAggregate {
        let id: String
        let name: String
        var chains = Set<String>()
        var positionCount = 0
        var usdBalance: Decimal = .zero
    }

    private struct NetworkAggregate {
        let id: String
        let title: String
        var positionCount = 0
        var usdBalance: Decimal = .zero
    }

    private static func makeAssetRows(
        positions: [Position],
        livePrices: [String: Decimal]
    ) -> [AssetTableRow] {
        let aggregates = positions.reduce(into: [String: AssetAggregate]()) { partialResult, position in
            for token in position.tokens where token.role != .reward {
                let key = makeAssetKey(for: token)
                let asset = token.asset
                let group = normalizedAccountGroup(for: position)
                var aggregate = partialResult[key] ?? AssetAggregate(
                    id: key,
                    assetID: asset?.id,
                    symbol: asset?.symbol ?? "Unknown",
                    name: asset?.name ?? asset?.symbol ?? "Unknown Asset",
                    category: asset?.category ?? .other,
                    coinGeckoID: asset?.coinGeckoId
                )

                switch token.role {
                case .borrow:
                    aggregate.borrowAmount += token.amount
                    aggregate.borrowSyncValue += token.usdValue
                case .balance, .supply, .stake, .lpToken:
                    aggregate.positiveAmount += token.amount
                    aggregate.positiveSyncValue += token.usdValue
                case .reward:
                    continue
                }

                aggregate.accountGroups.insert(group)
                partialResult[key] = aggregate
            }
        }

        return aggregates.values
            .compactMap { aggregate in
                guard aggregate.positiveAmount != .zero || aggregate.borrowAmount != .zero else {
                    return nil
                }

                let livePrice = aggregate.coinGeckoID.flatMap { livePrices[$0] }
                let fallbackPrice = fallbackPrice(for: aggregate)
                let price = livePrice ?? fallbackPrice ?? .zero
                let priceSource: AssetValueFormatter.PriceSource? = {
                    if livePrice != nil {
                        return .live
                    }

                    return fallbackPrice == nil ? nil : .syncFallback
                }()

                let value: Decimal
                let grossValue: Decimal

                if let livePrice {
                    value = aggregate.netAmount * livePrice
                    grossValue = aggregate.positiveAmount * livePrice
                } else {
                    value = aggregate.positiveSyncValue - aggregate.borrowSyncValue
                    grossValue = aggregate.positiveSyncValue
                }

                return AssetTableRow(
                    id: aggregate.id,
                    assetID: aggregate.assetID,
                    symbol: aggregate.symbol,
                    name: aggregate.name,
                    category: aggregate.category,
                    netAmount: aggregate.netAmount,
                    grossValue: grossValue,
                    price: price,
                    value: value,
                    priceSource: priceSource,
                    accountGroups: aggregate.accountGroups.sorted(),
                    searchIndex: "\(aggregate.symbol) \(aggregate.name)".lowercased()
                )
            }
            .sorted(by: compareAssetRows)
    }

    private static func makePlatformRows(
        positions: [Position]
    ) -> [PlatformTableRow] {
        let platformPositions = positions.filter { $0.positionType != .idle }
        let totalBalance = platformPositions.reduce(.zero) { $0 + $1.netUSDValue }

        let aggregates = platformPositions.reduce(into: [String: PlatformAggregate]()) { partialResult, position in
            let (id, name) = makePlatformIdentity(for: position)
            var aggregate = partialResult[id] ?? PlatformAggregate(id: id, name: name)
            aggregate.positionCount += 1
            aggregate.usdBalance += position.netUSDValue
            aggregate.chains.insert(networkBucketID(for: position.chain))
            partialResult[id] = aggregate
        }

        return aggregates.values
            .map { aggregate in
                PlatformTableRow(
                    id: aggregate.id,
                    name: aggregate.name,
                    share: totalBalance == .zero ? .zero : aggregate.usdBalance / totalBalance * 100,
                    networkCount: aggregate.chains.count,
                    positionCount: aggregate.positionCount,
                    usdBalance: aggregate.usdBalance
                )
            }
            .sorted(by: comparePlatformRows)
    }

    private static func makeNetworkRows(
        positions: [Position]
    ) -> [NetworkTableRow] {
        let totalBalance = positions.reduce(.zero) { $0 + $1.netUSDValue }

        let aggregates = positions.reduce(into: [String: NetworkAggregate]()) { partialResult, position in
            let id = networkBucketID(for: position.chain)
            let title = networkTitle(for: position.chain)
            var aggregate = partialResult[id] ?? NetworkAggregate(id: id, title: title)
            aggregate.positionCount += 1
            aggregate.usdBalance += position.netUSDValue
            partialResult[id] = aggregate
        }

        return aggregates.values
            .map { aggregate in
                NetworkTableRow(
                    id: aggregate.id,
                    title: aggregate.title,
                    share: totalBalance == .zero ? .zero : aggregate.usdBalance / totalBalance * 100,
                    positionCount: aggregate.positionCount,
                    usdBalance: aggregate.usdBalance
                )
            }
            .sorted(by: compareNetworkRows)
    }

    private static func fallbackPrice(
        for aggregate: AssetAggregate
    ) -> Decimal? {
        if aggregate.positiveAmount != .zero {
            return aggregate.positiveSyncValue / aggregate.positiveAmount
        }

        guard aggregate.borrowAmount != .zero else {
            return nil
        }

        return aggregate.borrowSyncValue / aggregate.borrowAmount
    }

    private static func normalizedAccountGroup(
        for position: Position
    ) -> String {
        let value = position.account?.group?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let value, value.isEmpty == false {
            return value
        }

        return "Ungrouped"
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

    private static func makePlatformIdentity(
        for position: Position
    ) -> (id: String, name: String) {
        if let protocolID = position.protocolId,
           let protocolName = position.protocolName,
           protocolName.isEmpty == false {
            return ("protocol:\(protocolID)", protocolName)
        }

        if let protocolID = position.protocolId {
            return ("protocol:\(protocolID)", protocolID)
        }

        if let protocolName = position.protocolName,
           protocolName.isEmpty == false {
            return ("protocol-name:\(protocolName)", protocolName)
        }

        if let accountID = position.account?.id,
           let accountName = position.account?.name {
            return ("account:\(accountID.uuidString)", accountName)
        }

        return ("position:\(position.id.uuidString)", "Unknown Platform")
    }

    private static func networkBucketID(
        for chain: Chain?
    ) -> String {
        chain?.rawValue ?? "off-chain-custodial"
    }

    private static func networkTitle(
        for chain: Chain?
    ) -> String {
        chain?.rawValue.capitalized ?? "Off-chain / Custodial"
    }

    private static func compareAssetRows(
        _ lhs: AssetTableRow,
        _ rhs: AssetTableRow
    ) -> Bool {
        if lhs.value != rhs.value {
            return lhs.value > rhs.value
        }

        return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
    }

    private static func comparePlatformRows(
        _ lhs: PlatformTableRow,
        _ rhs: PlatformTableRow
    ) -> Bool {
        if lhs.usdBalance != rhs.usdBalance {
            return lhs.usdBalance > rhs.usdBalance
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func compareNetworkRows(
        _ lhs: NetworkTableRow,
        _ rhs: NetworkTableRow
    ) -> Bool {
        if lhs.usdBalance != rhs.usdBalance {
            return lhs.usdBalance > rhs.usdBalance
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
