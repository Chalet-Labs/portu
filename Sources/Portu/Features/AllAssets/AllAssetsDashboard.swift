import Foundation
import PortuCore

/// A platform row's key: the position's protocol, else idle or unknown positions.
nonisolated enum PlatformKey: Hashable, Sendable {
    case protocolID(String)
    case idle
    case unknown

    init(_ position: PositionContext) {
        if let protocolID = position.protocolId {
            self = .protocolID(protocolID)
        } else {
            self = position.positionType == .idle ? .idle : .unknown
        }
    }

    /// The name when no position of the platform has a protocol name.
    var fallbackName: String {
        switch self {
        case let .protocolID(protocolID): protocolID
        case .idle: "Idle / Wallet"
        case .unknown: "Unknown"
        }
    }

    /// The last tie-break of the platform order.
    var sortKey: String {
        switch self {
        case let .protocolID(protocolID): "protocol:\(protocolID)"
        case .idle: "idle"
        case .unknown: "unknown"
        }
    }
}

nonisolated struct PlatformRowData: Identifiable, Equatable {
    let id: PlatformKey
    let name: String
    /// The F4 share; `nil` shows "—".
    let share: Decimal?
    let networkCount: Int
    let positionCount: Int
    let balance: Decimal
}

nonisolated struct NetworkRowData: Identifiable, Equatable {
    /// `nil` for off-chain and custodial positions.
    let id: Chain?
    let name: String
    /// The F4 share; `nil` shows "—".
    let share: Decimal?
    let positionCount: Int
    let balance: Decimal
}

/// A tab's hidden-balances line (F3), shown as its last table row (decided 2026-10-13).
nonisolated struct AllAssetsHiddenRow: Equatable {
    let rowCount: Int
    /// Every hidden row is dust; otherwise at least one is unpriced.
    let isAllDust: Bool
    /// The hidden net, in the display currency.
    let value: Decimal
    /// The line's F4 share on Platforms and Networks; `nil` shows "—", and the Assets tab has none.
    let share: Decimal?

    var title: String {
        HiddenBalancesLabel.title(rowCount: rowCount, isAllDust: isAllDust)
    }

    init(rowCount: Int, isAllDust: Bool, value: Decimal, share: Decimal?) {
        self.rowCount = rowCount
        self.isAllDust = isAllDust
        self.value = value
        self.share = share
    }

    /// The display-currency line of a list's hidden rows; `nil` when nothing is hidden.
    init?(_ hidden: HiddenBalances, rate: Decimal, share: Decimal?) {
        guard !hidden.isEmpty else { return nil }
        self.init(
            rowCount: hidden.rowCount,
            isAllDust: hidden.isAllDust,
            value: hidden.display(rate: rate).net,
            share: share)
    }
}

/// One row of an All Assets table as shown: `Table` has no footer, so the hidden line is a row.
nonisolated enum AllAssetsTableEntry<Row: Identifiable & Equatable>: Identifiable, Equatable {
    case row(Row)
    case hidden(AllAssetsHiddenRow)

    enum EntryID: Hashable {
        case row(Row.ID)
        case hidden
    }

    var id: EntryID {
        switch self {
        case let .row(row): .row(row.id)
        case .hidden: .hidden
        }
    }

    var row: Row? {
        if case let .row(row) = self {
            return row
        }
        return nil
    }

    var hidden: AllAssetsHiddenRow? {
        if case let .hidden(line) = self {
            return line
        }
        return nil
    }

    /// The rows in order, then the hidden line, which is always last.
    static func entries(_ rows: [Row], hidden: AllAssetsHiddenRow?) -> [Self] {
        rows.map(row) + (hidden.map { [.hidden($0)] } ?? [])
    }
}

enum AssetSortColumn: CaseIterable {
    case symbol
    case name
    case category
    case netAmount
    case price
    case value

    var defaultAscending: Bool {
        switch self {
        case .symbol, .name, .category:
            true
        case .netAmount, .price, .value:
            false
        }
    }
}

/// The Assets tab, in the display currency.
struct AssetsTabData: Equatable {
    /// The visible rows the search matches, unsorted.
    let rows: [AssetRowData]
    /// The hidden line; `nil` when nothing is hidden and while the search box is not empty.
    let hidden: AllAssetsHiddenRow?
    /// Visible rows + the hidden line, whatever the search.
    let total: Decimal

    /// The table as shown: the rows in the user's sort, then the hidden line.
    func entries(sortedBy column: AssetSortColumn, ascending: Bool) -> [AllAssetsTableEntry<AssetRowData>] {
        AllAssetsTableEntry.entries(
            AllAssetsFeature.sortedRows(rows, by: column, ascending: ascending),
            hidden: hidden)
    }
}

/// The Platforms tab, in the display currency.
struct PlatformsTabData: Equatable {
    /// The visible rows, largest balance first.
    let rows: [PlatformRowData]
    let hidden: AllAssetsHiddenRow?
    /// Visible rows + the hidden line.
    let total: Decimal

    var entries: [AllAssetsTableEntry<PlatformRowData>] {
        AllAssetsTableEntry.entries(rows, hidden: hidden)
    }
}

/// The Networks tab, in the display currency.
struct NetworksTabData: Equatable {
    /// The visible rows, largest balance first.
    let rows: [NetworkRowData]
    let hidden: AllAssetsHiddenRow?
    /// Visible rows + the hidden line.
    let total: Decimal

    var entries: [AllAssetsTableEntry<NetworkRowData>] {
        AllAssetsTableEntry.entries(rows, hidden: hidden)
    }
}

extension AllAssetsFeature {
    // MARK: - Assets

    /// One net row per asset (AGENT-DECIDED 5), every row kept, ignored and not-counted ones
    /// included. Token Settings lists the same rows.
    static func assetList(_ valuation: PortfolioValuation, settings: TokenDashboardSettings) -> DashboardList<UUID> {
        DashboardList(valuation.tokens, basis: .net, settings: settings) { $0.token.assetId }
    }

    /// The Assets tab: the visible asset rows the search matches and, while the search box is
    /// empty, the hidden line (U2). The search never changes the line's numbers or the total.
    static func assets(_ context: ValuationContext, searchText: String) -> AssetsTabData {
        let rate = context.usdToDisplayRate
        let list = assetList(context.valuation(), settings: context.settings)
        let rows = list.visibleRows.compactMap { AssetRowData($0, rate: rate) }
        return AssetsTabData(
            rows: filterRows(rows, searchText: searchText),
            hidden: searchText.isEmpty ? AllAssetsHiddenRow(list.hidden, rate: rate, share: nil) : nil,
            total: list.displayTotal(rate: rate))
    }

    /// The user's sort; equal rows by symbol, then asset ID. A missing price sorts lowest.
    static func sortedRows(_ rows: [AssetRowData], by column: AssetSortColumn, ascending: Bool) -> [AssetRowData] {
        rows.sorted { lhs, rhs in
            let result = compare(lhs, rhs, by: column)
            if result != .orderedSame {
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
            let symbolOrder = lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol)
            if symbolOrder != .orderedSame {
                return symbolOrder == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func compare(_ lhs: AssetRowData, _ rhs: AssetRowData, by column: AssetSortColumn) -> ComparisonResult {
        switch column {
        case .symbol:
            lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol)
        case .name:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .category:
            lhs.portfolioCategory.name.localizedCaseInsensitiveCompare(rhs.portfolioCategory.name)
        case .netAmount:
            compare(lhs.netAmount, rhs.netAmount)
        case .price:
            compare(lhs.price, rhs.price)
        case .value:
            compare(lhs.value, rhs.value)
        }
    }

    private static func compare(_ lhs: Decimal?, _ rhs: Decimal?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
        case (nil, nil):
            .orderedSame
        case (nil, _):
            .orderedAscending
        case (_, nil):
            .orderedDescending
        }
    }

    // MARK: - Platforms and Networks

    /// The Platforms tab: a net list per protocol (A7) with largest-remainder shares that include
    /// the hidden line (F4). `protocolNames` maps a position ID to its protocol name.
    static func platforms(_ context: ValuationContext, protocolNames: [UUID: String] = [:]) -> PlatformsTabData {
        let rate = context.usdToDisplayRate
        let list = DashboardList(context.valuation().tokens, basis: .net, settings: context.settings) {
            PlatformKey($0.position)
        }
        var names: [PlatformKey: String] = [:]
        for row in list.rows {
            names[row.key] = row.tokens.compactMap { protocolNames[$0.position.positionId] }.min(by: isOrderedBefore)
                ?? row.key.fallbackName
        }
        let ranked = list.ranked { lhs, rhs in
            isOrderedBefore(names[lhs.key] ?? "", lhs.key.sortKey, names[rhs.key] ?? "", rhs.key.sortKey)
        }
        let shares = ranked.shares()
        return PlatformsTabData(
            rows: zip(ranked.rows, rowShares(shares, count: ranked.rows.count)).map { row, share in
                let held = heldTokens(row)
                return PlatformRowData(
                    id: row.key,
                    name: names[row.key] ?? row.key.fallbackName,
                    share: share,
                    networkCount: Set(held.map(\.position.chain)).count,
                    positionCount: Set(held.map(\.position.positionId)).count,
                    balance: row.displayValue(rate: rate))
            },
            hidden: AllAssetsHiddenRow(ranked.hidden, rate: rate, share: shares?.hidden),
            total: ranked.displayTotal(rate: rate))
    }

    /// The Networks tab: a net list per chain (A7) with largest-remainder shares that include the
    /// hidden line (F4).
    static func networks(_ context: ValuationContext) -> NetworksTabData {
        let rate = context.usdToDisplayRate
        let list = DashboardList(context.valuation().tokens, basis: .net, settings: context.settings) {
            $0.position.chain
        }
        let ranked = list.ranked { lhs, rhs in
            isOrderedBefore(networkName(lhs.key), lhs.key?.rawValue ?? "", networkName(rhs.key), rhs.key?.rawValue ?? "")
        }
        let shares = ranked.shares()
        return NetworksTabData(
            rows: zip(ranked.rows, rowShares(shares, count: ranked.rows.count)).map { row, share in
                NetworkRowData(
                    id: row.key,
                    name: networkName(row.key),
                    share: share,
                    positionCount: Set(heldTokens(row).map(\.position.positionId)).count,
                    balance: row.displayValue(rate: rate))
            },
            hidden: AllAssetsHiddenRow(ranked.hidden, rate: rate, share: shares?.hidden),
            total: ranked.displayTotal(rate: rate))
    }

    private static func networkName(_ chain: Chain?) -> String {
        chain?.rawValue.capitalized ?? "Off-chain / Custodial"
    }

    /// The tokens "# Positions" and "# Networks" count: counted and not ignored (AGENT-DECIDED 8).
    private static func heldTokens(_ row: DashboardRow<some Hashable & Sendable>) -> [ValuedToken] {
        row.tokens.filter { $0.isCounted && !$0.isIgnored }
    }

    /// Each row's share, or "—" for every row when the list shows none.
    private static func rowShares(_ shares: ListShares?, count: Int) -> [Decimal?] {
        shares.map { $0.rows.map(Optional.some) } ?? Array(repeating: nil, count: count)
    }

    /// Equal balances: name in localized standard order, then key.
    private static func isOrderedBefore(_ lhsName: String, _ lhsKey: String, _ rhsName: String, _ rhsKey: String) -> Bool {
        if lhsName != rhsName {
            return isOrderedBefore(lhsName, rhsName)
        }
        return lhsKey < rhsKey
    }

    private static func isOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let order = lhs.localizedStandardCompare(rhs)
        return order == .orderedSame ? lhs < rhs : order == .orderedAscending
    }
}

enum AllAssetsFormat {
    /// A share to 0.1%, or "—" when the list shows none (F4).
    static func share(_ share: Decimal?) -> String {
        share?.formatted(.percent.precision(.fractionLength(1))) ?? "—"
    }
}
