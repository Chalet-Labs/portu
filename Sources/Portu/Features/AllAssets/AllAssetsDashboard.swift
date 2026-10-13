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
        ExposureLabels.hiddenRowTitle(rowCount: rowCount, isAllDust: isAllDust)
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

/// What the three tabs value: the active accounts' context and, for Platforms, the protocol name
/// of each position that contributes an input.
struct AllAssetsInputs {
    let context: ValuationContext
    let protocolNames: [UUID: String]
}

extension AllAssetsFeature {
    // MARK: - Assets

    /// The Assets tab. `liveDisplayPrices` and `historicalDisplayPrices` are today's display books,
    /// which the tab still prices from.
    static func assets(
        _ context: ValuationContext,
        searchText: String,
        liveDisplayPrices: [String: Decimal] = [:],
        historicalDisplayPrices: [String: Decimal] = [:]) -> AssetsTabData {
        let prices = OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: liveDisplayPrices,
            historical: historicalDisplayPrices)
        let eligible = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: context.inputs.map(\.token),
            prices: prices,
            overrides: context.overrides,
            settings: context.settings,
            usdToDisplayRate: context.usdToDisplayRate)
        let rows = aggregateRows(tokens: eligible, prices: prices, fallbackUSDToDisplayRate: context.usdToDisplayRate)
        return AssetsTabData(
            rows: filterRows(rows, searchText: searchText),
            hidden: nil,
            total: rows.reduce(Decimal.zero) { $0 + $1.value })
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

    /// The Platforms tab, from each active position's stored sync-time total.
    static func platforms(_ context: ValuationContext, protocolNames: [UUID: String] = [:]) -> PlatformsTabData {
        let positions = syncTotals(context)
        let rows = PlatformsTab.computeRows(from: positions.map { position, value in
            PlatformsTab.PlatformInput(
                chain: position.chain?.rawValue,
                protocolId: position.protocolId,
                protocolName: protocolNames[position.positionId],
                positionType: position.positionType,
                netValue: value)
        })
        return PlatformsTabData(
            rows: rows.map { row in
                PlatformRowData(
                    id: row.id == "__idle__" ? .idle : (row.id == "__unknown__" ? .unknown : .protocolID(row.id)),
                    name: row.name,
                    share: row.sharePercent,
                    networkCount: row.networkCount,
                    positionCount: row.positionCount,
                    balance: row.balance)
            },
            hidden: nil,
            total: positions.reduce(Decimal.zero) { $0 + $1.value })
    }

    /// The Networks tab, from each active position's stored sync-time total.
    static func networks(_ context: ValuationContext) -> NetworksTabData {
        let positions = syncTotals(context)
        let rows = NetworksTab.computeRows(from: positions.map { position, value in
            (chain: position.chain?.rawValue, netUSDValue: value)
        })
        return NetworksTabData(
            rows: rows.map { row in
                NetworkRowData(
                    id: Chain(rawValue: row.id),
                    name: row.name,
                    share: row.sharePercent,
                    positionCount: row.positionCount,
                    balance: row.usdBalance)
            },
            hidden: nil,
            total: positions.reduce(Decimal.zero) { $0 + $1.value })
    }

    /// Each position's raw sync-time total (A6, today's `netUSDValue`), in the display currency.
    private static func syncTotals(_ context: ValuationContext) -> [(position: PositionContext, value: Decimal)] {
        let valuation = PortfolioValuation(inputs: context.inputs, market: ValuationPriceInputs().market)
        return valuation.totals { $0.position }.map { position, totals in
            (position, totals.display(rate: context.usdToDisplayRate).syncTotal)
        }
    }
}

enum AllAssetsFormat {
    /// A share to 0.1%, or "—" when the list shows none (F4).
    static func share(_ share: Decimal?) -> String {
        share?.formatted(.percent.precision(.fractionLength(1))) ?? "—"
    }
}
