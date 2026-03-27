import Foundation
import PortuCore

@MainActor
@Observable
final class AllPositionsViewModel {
    private struct ProtocolIdentity: Hashable {
        let key: String
        let displayName: String
    }

    var selectedFilter: PositionFilter = .all

    let positions: [Position]

    var sections: [PositionSectionModel] {
        Self.makeSections(
            from: visiblePositions
        )
    }

    var protocolOptions: [String] {
        Self.makeProtocolOptions(from: visiblePositions)
    }

    init(positions: [Position] = []) {
        self.positions = positions.filter { $0.account?.isActive == true }
    }

    private var visiblePositions: [Position] {
        positions.filter { selectedFilter.matches($0) }
    }

    private static func makeSections(
        from positions: [Position]
    ) -> [PositionSectionModel] {
        let groupedBuckets = Dictionary(grouping: positions, by: bucketTitle(for:))

        return bucketOrder
            .compactMap { title in
                guard let bucketPositions = groupedBuckets[title], bucketPositions.isEmpty == false else {
                    return nil
                }

                let children = makeProtocolSections(from: bucketPositions)
                let bucketValue = bucketPositions.reduce(.zero) { $0 + $1.netUSDValue }

                return PositionSectionModel(
                    id: "bucket:\(title)",
                    title: title,
                    protocolName: nil,
                    chainLabel: nil,
                    healthFactor: nil,
                    value: bucketValue,
                    rows: [],
                    children: children
                )
            }
    }

    private static func makeProtocolSections(
        from positions: [Position]
    ) -> [PositionSectionModel] {
        let groupedProtocols = Dictionary(grouping: positions, by: protocolIdentity(for:))

        return groupedProtocols
            .map { identity, groupedPositions in
                let chainLabel = chainLabel(for: groupedPositions)
                let healthFactor = groupedPositions.compactMap(\.healthFactor).min()
                let rows = makeTokenRows(from: groupedPositions)
                let value = groupedPositions.reduce(.zero) { $0 + $1.netUSDValue }

                return PositionSectionModel(
                    id: identity.key,
                    title: identity.displayName,
                    protocolName: identity.displayName,
                    chainLabel: chainLabel,
                    healthFactor: healthFactor,
                    value: value,
                    rows: rows,
                    children: []
                )
            }
            .sorted(by: compareProtocolSections)
    }

    private static func makeTokenRows(
        from positions: [Position]
    ) -> [PositionTokenRowModel] {
        positions
            .flatMap { position in
                position.tokens.compactMap { token in
                    guard token.role != .reward else {
                        return nil
                    }

                    return PositionTokenRowModel(
                        id: token.id,
                        positionID: position.id,
                        symbol: token.asset?.symbol ?? "Unknown",
                        assetName: token.asset?.name ?? token.asset?.symbol ?? "Unknown Asset",
                        accountName: position.account?.name ?? "Unknown Account",
                        chainLabel: chainLabel(for: position),
                        role: token.role,
                        displayAmount: absoluteValue(of: token.amount),
                        displayValue: absoluteValue(of: token.usdValue)
                    )
                }
            }
            .sorted(by: compareTokenRows)
    }

    private static func makeProtocolOptions(
        from positions: [Position]
    ) -> [String] {
        Array(
            Set(
                positions.map { position in
                    protocolIdentity(for: position).displayName
                }
            )
        )
        .sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func bucketTitle(
        for position: Position
    ) -> String {
        switch position.positionType {
        case .idle:
            return position.chain == nil ? "Idle Exchanges" : "Idle Onchain"
        case .lending:
            return "Lending"
        case .liquidityPool:
            return "Liquidity Pool"
        case .staking:
            return "Staking"
        case .farming:
            return "Farming"
        case .vesting:
            return "Vesting"
        case .other:
            return "Other"
        }
    }

    private static var bucketOrder: [String] {
        [
            "Idle Onchain",
            "Idle Exchanges",
            "Lending",
            "Liquidity Pool",
            "Staking",
            "Farming",
            "Vesting",
            "Other"
        ]
    }

    private static func protocolIdentity(
        for position: Position
    ) -> ProtocolIdentity {
        let protocolID = trimmedNonEmpty(position.protocolId)
        let protocolName = trimmedNonEmpty(position.protocolName)
        let accountName = trimmedNonEmpty(position.account?.name)

        if let protocolID, let protocolName {
            return ProtocolIdentity(
                key: "protocol:\(protocolID)",
                displayName: protocolName
            )
        }

        if let protocolID {
            return ProtocolIdentity(
                key: "protocol:\(protocolID)",
                displayName: protocolID
            )
        }

        if let protocolName {
            return ProtocolIdentity(
                key: "protocol-name:\(protocolName.lowercased())",
                displayName: protocolName
            )
        }

        if let accountID = position.account?.id, let accountName {
            return ProtocolIdentity(
                key: "account:\(accountID.uuidString)",
                displayName: accountName
            )
        }

        return ProtocolIdentity(
            key: "position:\(position.id.uuidString)",
            displayName: "Unknown Protocol"
        )
    }

    private static func chainLabel(
        for position: Position
    ) -> String {
        if let chain = position.chain {
            return chainLabel(for: chain)
        }

        return "Off-chain / Custodial"
    }

    private static func chainLabel(
        for positions: [Position]
    ) -> String {
        let labels = Array(
            Set(positions.map { chainLabel(for: $0) })
        ).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return labels.count == 1 ? labels[0] : labels.joined(separator: " / ")
    }

    private static func chainLabel(
        for chain: Chain
    ) -> String {
        switch chain {
        case .ethereum:
            return "Ethereum"
        case .polygon:
            return "Polygon"
        case .arbitrum:
            return "Arbitrum"
        case .optimism:
            return "Optimism"
        case .base:
            return "Base"
        case .bsc:
            return "BSC"
        case .solana:
            return "Solana"
        case .bitcoin:
            return "Bitcoin"
        case .avalanche:
            return "Avalanche"
        case .monad:
            return "Monad"
        case .katana:
            return "Katana"
        }
    }

    private static func compareProtocolSections(
        _ lhs: PositionSectionModel,
        _ rhs: PositionSectionModel
    ) -> Bool {
        let lhsProtocol = lhs.protocolName ?? ""
        let rhsProtocol = rhs.protocolName ?? ""
        if lhsProtocol.caseInsensitiveCompare(rhsProtocol) != .orderedSame {
            return lhsProtocol.localizedCaseInsensitiveCompare(rhsProtocol) == .orderedAscending
        }

        let lhsChain = lhs.chainLabel ?? ""
        let rhsChain = rhs.chainLabel ?? ""
        if lhsChain.caseInsensitiveCompare(rhsChain) != .orderedSame {
            return lhsChain.localizedCaseInsensitiveCompare(rhsChain) == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private static func compareTokenRows(
        _ lhs: PositionTokenRowModel,
        _ rhs: PositionTokenRowModel
    ) -> Bool {
        let lhsPriority = tokenPriority(for: lhs.role)
        let rhsPriority = tokenPriority(for: rhs.role)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.displayValue != rhs.displayValue {
            return lhs.displayValue > rhs.displayValue
        }

        if lhs.symbol != rhs.symbol {
            return lhs.symbol < rhs.symbol
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func tokenPriority(
        for role: TokenRole
    ) -> Int {
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

    private static func absoluteValue(
        of value: Decimal
    ) -> Decimal {
        value < .zero ? -value : value
    }

    private static func trimmedNonEmpty(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
