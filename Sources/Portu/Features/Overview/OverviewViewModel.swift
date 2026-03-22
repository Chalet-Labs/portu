import Foundation
import PortuCore

struct TopAssetSlice: Identifiable, Sendable {
    let id: String
    let label: String
    let value: Decimal
    let shareOfPortfolio: Decimal
}

struct OverviewTokenRow: Identifiable, Sendable {
    let id: UUID
    let positionID: UUID
    let assetKey: String
    let symbol: String
    let assetName: String
    let assetCategory: AssetCategory
    let chainLabel: String
    let accountName: String
    let networkAccountLabel: String
    let amount: Decimal
    let displayPrice: Decimal
    let displayValue: Decimal
    let role: TokenRole
    let positionType: PositionType
    let protocolName: String
    let healthFactor: Double?
    let priceSource: AssetValueFormatter.PriceSource?
    let changeContribution24h: Decimal

    var roleLabel: String {
        AssetValueFormatter.roleLabel(for: role)
    }
}

@MainActor
@Observable
final class OverviewViewModel {
    var selectedTab: OverviewTab = .keyChanges

    let positions: [Position]
    let snapshots: [PortfolioSnapshot]
    let prices: [String: Decimal]
    let changes24h: [String: Decimal]

    var totalValue: Decimal
    var absoluteChange24h: Decimal
    var percentageChange24h: Decimal
    var topAssets: [TopAssetSlice]
    var keyChangeRows: [OverviewTokenRow]
    var idleStableRows: [OverviewTokenRow]
    var idleMajorRows: [OverviewTokenRow]
    var borrowingRows: [OverviewTokenRow]

    var latestSnapshot: PortfolioSnapshot? {
        QuerySnapshots.latest(snapshots)
    }

    init(
        positions: [Position],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        snapshots: [PortfolioSnapshot] = []
    ) {
        let activePositions = positions.filter { $0.account?.isActive == true }
        let orderedSnapshots = QuerySnapshots.sortedByTimestamp(snapshots)

        self.positions = activePositions
        self.snapshots = orderedSnapshots
        self.prices = prices
        self.changes24h = changes24h

        let totalValue = Self.computeTotalValue(positions: activePositions)
        let absoluteChange24h = Self.computeAbsoluteChange24h(
            positions: activePositions,
            prices: prices,
            changes24h: changes24h
        )
        let percentageChange24h = Self.computePercentageChange24h(
            absoluteChange24h: absoluteChange24h,
            totalValue: totalValue
        )

        let tokenRows = Self.makeRows(
            positions: activePositions,
            prices: prices,
            changes24h: changes24h
        )

        self.totalValue = totalValue
        self.absoluteChange24h = absoluteChange24h
        self.percentageChange24h = percentageChange24h
        keyChangeRows = Self.makeKeyChangeRows(from: tokenRows)
        idleStableRows = Self.makeIdleRows(
            from: tokenRows,
            matching: [.stablecoin, .fiat]
        )
        idleMajorRows = Self.makeIdleRows(from: tokenRows, category: .major)
        borrowingRows = Self.makeBorrowingRows(
            from: tokenRows,
            positions: activePositions
        )
        topAssets = Self.makeTopAssets(from: tokenRows)
    }

    func rows(for tab: OverviewTab) -> [OverviewTokenRow] {
        switch tab {
        case .keyChanges:
            return keyChangeRows
        case .idleStables:
            return idleStableRows
        case .idleMajors:
            return idleMajorRows
        case .borrowing:
            return borrowingRows
        }
    }

    private static func computeTotalValue(
        positions: [Position]
    ) -> Decimal {
        positions.reduce(.zero) { $0 + $1.netUSDValue }
    }

    private static func computeAbsoluteChange24h(
        positions: [Position],
        prices: [String: Decimal],
        changes24h: [String: Decimal]
    ) -> Decimal {
        positions.reduce(.zero) { partialResult, position in
            partialResult + position.tokens.reduce(.zero) { tokenTotal, token in
                tokenTotal + AssetValueFormatter.changeContribution24h(
                    for: token,
                    livePrices: prices,
                    changes24h: changes24h
                )
            }
        }
    }

    private static func computePercentageChange24h(
        absoluteChange24h: Decimal,
        totalValue: Decimal
    ) -> Decimal {
        guard totalValue != .zero else {
            return .zero
        }

        return absoluteChange24h / totalValue * 100
    }

    private static func makeRows(
        positions: [Position],
        prices: [String: Decimal],
        changes24h: [String: Decimal]
    ) -> [OverviewTokenRow] {
        positions.flatMap { position in
            position.tokens.compactMap { token in
                guard token.role != .reward else {
                    return nil
                }

                let chainLabel = makeChainLabel(for: position)
                let accountName = makeAccountName(for: position)

                return OverviewTokenRow(
                    id: token.id,
                    positionID: position.id,
                    assetKey: makeAssetKey(for: token),
                    symbol: token.asset?.symbol ?? "Unknown",
                    assetName: token.asset?.name ?? token.asset?.symbol ?? "Unknown Asset",
                    assetCategory: token.asset?.category ?? .other,
                    chainLabel: chainLabel,
                    accountName: accountName,
                    networkAccountLabel: makeNetworkAccountLabel(
                        chainLabel: chainLabel,
                        accountLabel: accountName
                    ),
                    amount: token.amount,
                    displayPrice: AssetValueFormatter.displayPrice(
                        for: token,
                        livePrices: prices
                    ),
                    displayValue: AssetValueFormatter.displayValue(
                        for: token,
                        livePrices: prices
                    ),
                    role: token.role,
                    positionType: position.positionType,
                    protocolName: position.protocolName ?? "Unknown Protocol",
                    healthFactor: position.healthFactor,
                    priceSource: AssetValueFormatter.priceSource(
                        for: token,
                        livePrices: prices
                    ),
                    changeContribution24h: AssetValueFormatter.changeContribution24h(
                        for: token,
                        livePrices: prices,
                        changes24h: changes24h
                    )
                )
            }
        }
    }

    private static func makeBorrowingRows(
        from rows: [OverviewTokenRow],
        positions: [Position]
    ) -> [OverviewTokenRow] {
        let borrowingPositionIDs = Set(
            positions
                .filter { position in
                    position.tokens.contains { $0.role == .borrow }
                }
                .map(\.id)
        )

        return rows
            .filter { borrowingPositionIDs.contains($0.positionID) }
            .sorted(by: compareBorrowingRows)
    }

    private static func makeKeyChangeRows(
        from rows: [OverviewTokenRow]
    ) -> [OverviewTokenRow] {
        rows
            .filter { $0.role != .borrow }
            .sorted {
                absoluteValue(of: $0.changeContribution24h)
                    > absoluteValue(of: $1.changeContribution24h)
            }
    }

    private static func makeIdleRows(
        from rows: [OverviewTokenRow],
        category: AssetCategory
    ) -> [OverviewTokenRow] {
        makeIdleRows(from: rows, matching: [category])
    }

    private static func makeIdleRows(
        from rows: [OverviewTokenRow],
        matching categories: Set<AssetCategory>
    ) -> [OverviewTokenRow] {
        rows
            .filter { row in
                row.role != .borrow
                    && row.positionType == .idle
                    && categories.contains(row.assetCategory)
            }
            .sorted { $0.displayValue > $1.displayValue }
    }

    private static func makeTopAssets(
        from rows: [OverviewTokenRow]
    ) -> [TopAssetSlice] {
        let valuesByAsset = rows.reduce(into: [String: (label: String, value: Decimal)]()) { partialResult, row in
            guard row.role != .borrow else {
                return
            }
            let current = partialResult[row.assetKey] ?? (row.symbol, .zero)
            partialResult[row.assetKey] = (current.label, current.value + row.displayValue)
        }
        let totalVisibleValue = valuesByAsset.values.reduce(.zero) { $0 + $1.value }

        return valuesByAsset
            .map { assetKey, entry in
                TopAssetSlice(
                    id: assetKey,
                    label: entry.label,
                    value: entry.value,
                    shareOfPortfolio: totalVisibleValue == .zero
                        ? .zero
                        : (entry.value / totalVisibleValue * 100)
                )
            }
            .sorted { $0.value > $1.value }
    }

    private static func makeChainLabel(for position: Position) -> String {
        position.chain?.rawValue.capitalized ?? "Off-chain"
    }

    private static func makeAccountName(for position: Position) -> String {
        position.account?.name ?? "Unknown Account"
    }

    private static func makeNetworkAccountLabel(
        chainLabel: String,
        accountLabel: String
    ) -> String {
        return "\(chainLabel) / \(accountLabel)"
    }

    private static func absoluteValue(of value: Decimal) -> Decimal {
        value < .zero ? -value : value
    }

    private static func makeAssetKey(for token: PositionToken) -> String {
        if let coinGeckoId = token.asset?.coinGeckoId {
            return "cg:\(coinGeckoId)"
        }
        if let assetID = token.asset?.id {
            return "asset:\(assetID.uuidString)"
        }
        return "token:\(token.id.uuidString)"
    }

    private static func compareBorrowingRows(
        _ lhs: OverviewTokenRow,
        _ rhs: OverviewTokenRow
    ) -> Bool {
        if lhs.protocolName != rhs.protocolName {
            return lhs.protocolName < rhs.protocolName
        }

        if lhs.chainLabel != rhs.chainLabel {
            return lhs.chainLabel < rhs.chainLabel
        }

        if lhs.accountName != rhs.accountName {
            return lhs.accountName < rhs.accountName
        }

        let lhsPriority = borrowingPriority(for: lhs.role)
        let rhsPriority = borrowingPriority(for: rhs.role)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.displayValue > rhs.displayValue
    }

    private static func borrowingPriority(for role: TokenRole) -> Int {
        switch role {
        case .borrow:
            return 0
        case .supply:
            return 1
        case .balance:
            return 2
        case .stake:
            return 3
        case .lpToken:
            return 4
        case .reward:
            return 5
        }
    }
}
