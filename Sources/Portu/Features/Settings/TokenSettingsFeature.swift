import Foundation
import PortuCore

enum TokenPricingSource: String, CaseIterable, Equatable {
    case live = "Live"
    case close = "Close"
    case syncTime = "Sync-time"
    case manual = "Manual"
    case unpriced = "Unpriced"
}

enum TokenSettingsFilter: String, CaseIterable, Equatable, Identifiable {
    case all = "All"
    case unpriced = "Unpriced"
    case belowThreshold = "Below Threshold"
    case ignored = "Ignored"
    case notCounted = "Not Counted"
    case manualPrice = "Manual Price"
    case mappedPriceSource = "Mapped Price Source"

    var id: String {
        rawValue
    }
}

struct TokenSettingsRow: Equatable, Identifiable {
    let id: UUID
    let assetId: UUID
    let symbol: String
    let name: String
    /// Σ role-signed amounts of the counted tokens; of every token on an ignored or not-counted row.
    let amount: Decimal
    /// Σ contributions; `nil` for an ignored or unpriced asset, which is listed with no value. A
    /// not-counted asset shows its tokens' unsigned value instead, which counts nowhere.
    let value: Decimal?
    let portfolioCategory: PortfolioCategorySnapshot
    /// `nil` (shown "—") when no counted token decides a source.
    let pricingSource: TokenPricingSource?
    /// F1, independent of the toggles; `alwaysShow` is its own flag.
    let status: RowStatus
    let alwaysShow: Bool
    /// The asset's override ignores it. It beats every status for the badge, the count and the filter.
    let isIgnored: Bool
    let coinGeckoId: String?
    let logoURL: String?
    /// Currency the `value` is denominated in (the display currency).
    let currency: FiatCurrency
    let override: TokenPricingOverrideSnapshot?

    init(
        assetId: UUID,
        symbol: String,
        name: String,
        amount: Decimal,
        value: Decimal?,
        portfolioCategory: PortfolioCategorySnapshot,
        pricingSource: TokenPricingSource?,
        status: RowStatus,
        alwaysShow: Bool,
        isIgnored: Bool,
        coinGeckoId: String?,
        logoURL: String?,
        currency: FiatCurrency = .default,
        override: TokenPricingOverrideSnapshot?) {
        self.id = assetId
        self.assetId = assetId
        self.symbol = symbol
        self.name = name
        self.amount = amount
        self.value = value
        self.portfolioCategory = portfolioCategory
        self.pricingSource = pricingSource
        self.status = status
        self.alwaysShow = alwaysShow
        self.isIgnored = isIgnored
        self.coinGeckoId = coinGeckoId
        self.logoURL = logoURL
        self.currency = currency
        self.override = override
    }
}

struct TokenSettingsCounts: Equatable {
    let all: Int
    let unpriced: Int
    let belowThreshold: Int
    let ignored: Int
    let notCounted: Int
    let manualPrice: Int
    let mappedPriceSource: Int
}

struct TokenSettingsResult: Equatable {
    let rows: [TokenSettingsRow]
    let totalMatches: Int
    let counts: TokenSettingsCounts
}

enum TokenSettingsFeature {
    static let displayLimit = 100

    static func overridesByAssetId(_ overrides: [TokenPricingOverrideSnapshot]) -> [UUID: TokenPricingOverrideSnapshot] {
        TokenPricingOverrideFeature.overridesByAssetId(overrides)
    }

    static func applyIdentityMappings(
        to tokens: [TokenEntry],
        mappings: [TokenIdentityMappingSnapshot],
        overrides: [TokenPricingOverrideSnapshot]) -> [TokenEntry] {
        let mappingMap = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        let overrideMap = overridesByAssetId(overrides)

        return tokens.map { token in
            let override = overrideMap[token.assetId]
            let coinGeckoId = resolvedCoinGeckoID(token: token, override: override)
                ?? TokenIdentityMappingFeature.mappedCoinGeckoID(
                    for: token.onchainIdentity,
                    mappingsByIdentity: mappingMap)
            guard coinGeckoId != token.coinGeckoId else { return token }
            return tokenEntry(
                from: token,
                coinGeckoId: coinGeckoId,
                usdValue: token.usdValue)
        }
    }

    static func dashboardEligibleTokens(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults,
        usdToDisplayRate: Decimal = 1) -> [TokenEntry] {
        let overrideMap = overridesByAssetId(overrides)
        return dashboardEligibleTokens(
            tokens: tokens,
            prices: prices,
            overrideMap: overrideMap,
            settings: settings,
            usdToDisplayRate: usdToDisplayRate)
    }

    static func dashboardEligibleTokens(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrideMap: [UUID: TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults,
        usdToDisplayRate: Decimal = 1) -> [TokenEntry] {
        tokens.compactMap { token in
            let override = overrideMap[token.assetId]
            guard
                isDashboardEligible(
                    token: token,
                    prices: prices,
                    override: override,
                    settings: settings,
                    usdToDisplayRate: usdToDisplayRate)
            else {
                return nil
            }
            return dashboardAdjustedToken(from: token, override: override)
        }
    }

    static func isDashboardEligible(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings = .defaults,
        usdToDisplayRate: Decimal = 1) -> Bool {
        guard token.amount > 0 else { return false }
        guard token.role.isPositive || token.role.isBorrow else { return false }
        guard override?.isIgnored != true else { return false }
        if override?.alwaysShow == true {
            return true
        }

        guard
            let value = resolvedDisplayValue(
                token: token,
                prices: prices,
                override: override,
                usdToDisplayRate: usdToDisplayRate)
        else {
            return !settings.hideUnpriced
        }

        // The live price map is already in the display currency, so the USD dust
        // threshold must be scaled by the same rate to stay comparable.
        if absolute(value) < normalizedThreshold(settings.minimumDashboardValue) * usdToDisplayRate {
            return !settings.hideDust
        }
        return true
    }

    /// The Token Settings list over the active accounts' context: the module's asset rows (the
    /// Assets tab's list), every row and never only the visible ones, then the search, the filter
    /// and the cap. The counts cover every row the search matches.
    static func result(
        _ context: ValuationContext,
        filter: TokenSettingsFilter,
        searchText: String,
        currency: FiatCurrency = .default,
        limit: Int = displayLimit) -> TokenSettingsResult {
        let overrideMap = TokenPricingOverrideFeature.overridesByAssetId(context.overrides)
        let searchedRows = AllAssetsFeature.assetList(context.valuation(), settings: context.settings).rows
            .compactMap { row in
                TokenSettingsRow(row, override: overrideMap[row.key], currency: currency, rate: context.usdToDisplayRate)
            }
            .filter { row in
                matchesSearch(row: row, searchText: searchText)
            }
            .sorted(by: sortRows)

        let counts = counts(for: searchedRows)
        let filteredRows = searchedRows.filter { row in
            matchesFilter(row: row, filter: filter)
        }
        let cappedRows = Array(filteredRows.prefix(max(limit, 0)))

        return TokenSettingsResult(
            rows: cappedRows,
            totalMatches: filteredRows.count,
            counts: counts)
    }

    /// No identity mappings here, as before: the mapped CoinGecko ID only applies in PortuCore valuation.
    static func resolvedCoinGeckoID(
        token: TokenEntry,
        override: TokenPricingOverrideSnapshot?) -> String? {
        TokenPricingOverrideFeature.resolvedCoinGeckoID(token: token, override: override)
    }

    static func resolvedPriceID(
        token: TokenEntry,
        override: TokenPricingOverrideSnapshot?) -> String? {
        TokenPricingOverrideFeature.resolvedPriceID(token: token, override: override)
    }

    private static func counts(for rows: [TokenSettingsRow]) -> TokenSettingsCounts {
        TokenSettingsCounts(
            all: rows.count,
            unpriced: rows.count(where: { matchesFilter(row: $0, filter: .unpriced) }),
            belowThreshold: rows.count(where: { matchesFilter(row: $0, filter: .belowThreshold) }),
            ignored: rows.count(where: { matchesFilter(row: $0, filter: .ignored) }),
            notCounted: rows.count(where: { matchesFilter(row: $0, filter: .notCounted) }),
            manualPrice: rows.count(where: { matchesFilter(row: $0, filter: .manualPrice) }),
            mappedPriceSource: rows.count(where: { matchesFilter(row: $0, filter: .mappedPriceSource) }))
    }

    /// Ignore comes first, as on token-level rows: an ignored asset is never also Not Counted.
    private static func matchesFilter(row: TokenSettingsRow, filter: TokenSettingsFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .unpriced:
            !row.isIgnored && row.status == .unpriced
        case .belowThreshold:
            !row.isIgnored && row.status == .dust
        case .ignored:
            row.isIgnored
        case .notCounted:
            !row.isIgnored && row.status == .notCounted
        case .manualPrice:
            sanitizedManualPrice(row.override?.manualPriceUSD) != nil
        case .mappedPriceSource:
            normalizedCoinGeckoID(row.override?.coinGeckoIdOverride) != nil
        }
    }

    private static func matchesSearch(row: TokenSettingsRow, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return row.symbol.localizedCaseInsensitiveContains(query)
            || row.name.localizedCaseInsensitiveContains(query)
            || (row.coinGeckoId?.localizedCaseInsensitiveContains(query) ?? false)
    }

    /// Counted rows with a value first, by value descending; then the rows that do not count (ignored,
    /// unpriced, not counted). Ties and the trailing group: symbol, then asset ID.
    private static func sortRows(_ lhs: TokenSettingsRow, _ rhs: TokenSettingsRow) -> Bool {
        let lhsValue = sortValue(lhs)
        let rhsValue = sortValue(rhs)
        if lhsValue != rhsValue {
            switch (lhsValue, rhsValue) {
            case let (lhs?, rhs?): return lhs > rhs
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        let symbolOrder = lhs.symbol.localizedStandardCompare(rhs.symbol)
        if symbolOrder != .orderedSame {
            return symbolOrder == .orderedAscending
        }
        return lhs.assetId.uuidString < rhs.assetId.uuidString
    }

    /// A not-counted row's value counts nowhere, so it does not rank.
    private static func sortValue(_ row: TokenSettingsRow) -> Decimal? {
        row.status == .notCounted ? nil : row.value
    }

    static func dashboardAdjustedToken(
        from token: TokenEntry,
        override: TokenPricingOverrideSnapshot?) -> TokenEntry {
        if let manualPrice = sanitizedManualPrice(override?.manualPriceUSD) {
            return tokenEntry(
                from: token,
                coinGeckoId: nil,
                preserveOnchainIdentity: false,
                usdValue: token.amount * manualPrice)
        }
        return tokenEntry(
            from: token,
            coinGeckoId: resolvedCoinGeckoID(token: token, override: override),
            usdValue: token.usdValue)
    }
}
