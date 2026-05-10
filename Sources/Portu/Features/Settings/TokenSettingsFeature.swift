import Foundation
import PortuCore

struct TokenDashboardSettings: Equatable {
    static let minimumDashboardValueKey = "tokenSettings.minimumDashboardValue"
    static let hideUnpricedKey = "tokenSettings.hideUnpriced"
    static let hideDustKey = "tokenSettings.hideDust"
    static let defaultMinimumDashboardValue: Decimal = 1
    static let defaults = TokenDashboardSettings()

    var minimumDashboardValue: Decimal
    var hideUnpriced: Bool
    var hideDust: Bool

    init(
        minimumDashboardValue: Decimal = Self.defaultMinimumDashboardValue,
        hideUnpriced: Bool = true,
        hideDust: Bool = true) {
        self.minimumDashboardValue = minimumDashboardValue
        self.hideUnpriced = hideUnpriced
        self.hideDust = hideDust
    }
}

struct TokenPricingOverrideSnapshot: Equatable, Identifiable {
    var id: UUID
    var assetId: UUID
    var manualPriceUSD: Decimal?
    var coinGeckoIdOverride: String?
    var isIgnored: Bool
    var alwaysShow: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        assetId: UUID,
        manualPriceUSD: Decimal? = nil,
        coinGeckoIdOverride: String? = nil,
        isIgnored: Bool = false,
        alwaysShow: Bool = false,
        notes: String = "") {
        self.id = id
        self.assetId = assetId
        self.manualPriceUSD = manualPriceUSD
        self.coinGeckoIdOverride = coinGeckoIdOverride
        self.isIgnored = isIgnored
        self.alwaysShow = alwaysShow
        self.notes = notes
    }

    @MainActor
    init(_ override: TokenPricingOverride) {
        self.init(
            id: override.id,
            assetId: override.assetId,
            manualPriceUSD: override.manualPriceUSD,
            coinGeckoIdOverride: override.coinGeckoIdOverride,
            isIgnored: override.isIgnored,
            alwaysShow: override.alwaysShow,
            notes: override.notes)
    }
}

enum TokenPricingSource: String, CaseIterable, Equatable {
    case live = "Live"
    case syncTime = "Sync-time"
    case manual = "Manual"
    case unpriced = "Unpriced"
}

enum TokenVisibilityStatus: String, Equatable {
    case visible = "Visible"
    case dust = "Dust"
    case ignored = "Ignored"
    case alwaysShow = "Always Show"
    case unpriced = "Unpriced"
}

enum TokenSettingsFilter: String, CaseIterable, Equatable, Identifiable {
    case all = "All"
    case unpriced = "Unpriced"
    case belowThreshold = "Below Threshold"
    case ignored = "Ignored"
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
    let amount: Decimal
    let price: Decimal
    let value: Decimal
    let portfolioCategory: PortfolioCategorySnapshot
    let pricingSource: TokenPricingSource
    let visibilityStatus: TokenVisibilityStatus
    let coinGeckoId: String?
    let logoURL: String?
    let override: TokenPricingOverrideSnapshot?

    init(
        assetId: UUID,
        symbol: String,
        name: String,
        amount: Decimal,
        price: Decimal,
        value: Decimal,
        portfolioCategory: PortfolioCategorySnapshot,
        pricingSource: TokenPricingSource,
        visibilityStatus: TokenVisibilityStatus,
        coinGeckoId: String?,
        logoURL: String?,
        override: TokenPricingOverrideSnapshot?) {
        self.id = assetId
        self.assetId = assetId
        self.symbol = symbol
        self.name = name
        self.amount = amount
        self.price = price
        self.value = value
        self.portfolioCategory = portfolioCategory
        self.pricingSource = pricingSource
        self.visibilityStatus = visibilityStatus
        self.coinGeckoId = coinGeckoId
        self.logoURL = logoURL
        self.override = override
    }
}

struct TokenSettingsCounts: Equatable {
    let all: Int
    let unpriced: Int
    let belowThreshold: Int
    let ignored: Int
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
        Dictionary(overrides.map { ($0.assetId, $0) }, uniquingKeysWith: { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
        })
    }

    static func applyPriceOverrides(
        to tokens: [TokenEntry],
        overrides: [TokenPricingOverrideSnapshot]) -> [TokenEntry] {
        let overrideMap = overridesByAssetId(overrides)
        return tokens.map { token in
            guard let override = overrideMap[token.assetId] else { return token }
            return tokenEntry(
                from: token,
                coinGeckoId: resolvedCoinGeckoID(token: token, override: override),
                usdValue: token.usdValue)
        }
    }

    static func dashboardEligibleTokens(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults) -> [TokenEntry] {
        let overrideMap = overridesByAssetId(overrides)
        return tokens.compactMap { token in
            let override = overrideMap[token.assetId]
            guard isDashboardEligible(token: token, prices: prices, override: override, settings: settings) else {
                return nil
            }
            return dashboardToken(from: token, override: override)
        }
    }

    static func isDashboardEligible(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings = .defaults) -> Bool {
        guard token.amount > 0 else { return false }
        guard token.role.isPositive || token.role.isBorrow else { return false }
        guard override?.isIgnored != true else { return false }
        if override?.alwaysShow == true { return true }

        guard let value = resolvedValue(token: token, prices: prices, override: override) else {
            return !settings.hideUnpriced
        }

        if absolute(value) < normalizedThreshold(settings.minimumDashboardValue) {
            return !settings.hideDust
        }
        return true
    }

    static func rows(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults,
        filter: TokenSettingsFilter,
        searchText: String,
        limit: Int = displayLimit) -> TokenSettingsResult {
        let overrideMap = overridesByAssetId(overrides)
        let searchedRows = aggregateTokens(tokens).map { token in
            makeRow(
                token: token,
                prices: prices,
                override: overrideMap[token.assetId],
                settings: settings)
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

    static func resolvedCoinGeckoID(
        token: TokenEntry,
        override: TokenPricingOverrideSnapshot?) -> String? {
        normalizedCoinGeckoID(override?.coinGeckoIdOverride) ?? normalizedCoinGeckoID(token.coinGeckoId)
    }

    static func resolvedPrice(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal? {
        if let manualPrice = sanitizedManualPrice(override?.manualPriceUSD) {
            return manualPrice
        }
        if
            let coinGeckoId = resolvedCoinGeckoID(token: token, override: override),
            let price = prices[coinGeckoId] {
            return price
        }
        guard token.amount != 0, token.usdValue != 0 else { return nil }
        return token.usdValue / token.amount
    }

    static func resolvedValue(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal? {
        guard token.amount != 0 else { return nil }
        guard let price = resolvedPrice(token: token, prices: prices, override: override) else { return nil }
        return token.amount * price
    }

    private static func aggregateTokens(_ tokens: [TokenEntry]) -> [TokenEntry] {
        var aggregates: [UUID: TokenAggregate] = [:]
        for token in tokens {
            if var aggregate = aggregates[token.assetId] {
                aggregate.add(token)
                aggregates[token.assetId] = aggregate
            } else {
                aggregates[token.assetId] = TokenAggregate(token)
            }
        }
        return aggregates.values.map { aggregate in
            tokenEntry(
                from: aggregate.base,
                coinGeckoId: aggregate.coinGeckoId,
                amount: aggregate.netAmount,
                usdValue: aggregate.netUSDValue,
                logoURL: aggregate.logoURL)
        }
    }

    private static func makeRow(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings) -> TokenSettingsRow {
        let price = resolvedPrice(token: token, prices: prices, override: override)
        let value = resolvedValue(token: token, prices: prices, override: override)
        let source = pricingSource(token: token, prices: prices, override: override)
        let status = visibilityStatus(
            value: value,
            override: override,
            settings: settings)

        return TokenSettingsRow(
            assetId: token.assetId,
            symbol: token.symbol,
            name: token.name,
            amount: token.amount,
            price: price ?? 0,
            value: value ?? 0,
            portfolioCategory: token.portfolioCategory,
            pricingSource: source,
            visibilityStatus: status,
            coinGeckoId: resolvedCoinGeckoID(token: token, override: override),
            logoURL: token.logoURL,
            override: override)
    }

    private static func pricingSource(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> TokenPricingSource {
        if sanitizedManualPrice(override?.manualPriceUSD) != nil {
            return .manual
        }
        if
            let coinGeckoId = resolvedCoinGeckoID(token: token, override: override),
            prices[coinGeckoId] != nil {
            return .live
        }
        if token.amount != 0, token.usdValue != 0 {
            return .syncTime
        }
        return .unpriced
    }

    private static func visibilityStatus(
        value: Decimal?,
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings) -> TokenVisibilityStatus {
        if override?.isIgnored == true {
            return .ignored
        }
        if override?.alwaysShow == true {
            return .alwaysShow
        }
        guard let value else {
            return .unpriced
        }
        if absolute(value) < normalizedThreshold(settings.minimumDashboardValue) {
            return .dust
        }
        return .visible
    }

    private static func counts(for rows: [TokenSettingsRow]) -> TokenSettingsCounts {
        TokenSettingsCounts(
            all: rows.count,
            unpriced: rows.count(where: { $0.visibilityStatus == .unpriced }),
            belowThreshold: rows.count(where: { $0.visibilityStatus == .dust }),
            ignored: rows.count(where: { $0.visibilityStatus == .ignored }),
            manualPrice: rows.count(where: { $0.pricingSource == .manual }),
            mappedPriceSource: rows.count(where: { normalizedCoinGeckoID($0.override?.coinGeckoIdOverride) != nil }))
    }

    private static func matchesFilter(row: TokenSettingsRow, filter: TokenSettingsFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .unpriced:
            row.visibilityStatus == .unpriced
        case .belowThreshold:
            row.visibilityStatus == .dust
        case .ignored:
            row.visibilityStatus == .ignored
        case .manualPrice:
            row.pricingSource == .manual
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

    private static func sortRows(_ lhs: TokenSettingsRow, _ rhs: TokenSettingsRow) -> Bool {
        if lhs.value == rhs.value {
            let symbolOrder = lhs.symbol.localizedStandardCompare(rhs.symbol)
            if symbolOrder != .orderedSame {
                return symbolOrder == .orderedAscending
            }
            return lhs.assetId.uuidString < rhs.assetId.uuidString
        }
        return lhs.value > rhs.value
    }

    private static func dashboardToken(
        from token: TokenEntry,
        override: TokenPricingOverrideSnapshot?) -> TokenEntry {
        if let manualPrice = sanitizedManualPrice(override?.manualPriceUSD) {
            return tokenEntry(
                from: token,
                coinGeckoId: nil,
                usdValue: token.amount * manualPrice)
        }
        return tokenEntry(
            from: token,
            coinGeckoId: resolvedCoinGeckoID(token: token, override: override),
            usdValue: token.usdValue)
    }

    private static func tokenEntry(
        from token: TokenEntry,
        coinGeckoId: String?,
        amount: Decimal? = nil,
        usdValue: Decimal,
        logoURL: String? = nil) -> TokenEntry {
        TokenEntry(
            assetId: token.assetId,
            symbol: token.symbol,
            name: token.name,
            category: token.category,
            portfolioCategory: token.portfolioCategory,
            coinGeckoId: coinGeckoId,
            role: token.role,
            amount: amount ?? token.amount,
            usdValue: usdValue,
            logoURL: logoURL ?? token.logoURL)
    }

    private static func normalizedCoinGeckoID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func sanitizedManualPrice(_ price: Decimal?) -> Decimal? {
        guard let price, price > 0 else { return nil }
        return price
    }

    private static func normalizedThreshold(_ value: Decimal) -> Decimal {
        value < 0 ? 0 : value
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private struct TokenAggregate {
        var base: TokenEntry
        var coinGeckoId: String?
        var logoURL: String?
        var positiveAmount: Decimal = 0
        var borrowAmount: Decimal = 0
        var positiveUSDValue: Decimal = 0
        var borrowUSDValue: Decimal = 0

        var netAmount: Decimal {
            positiveAmount - borrowAmount
        }

        var netUSDValue: Decimal {
            positiveUSDValue - borrowUSDValue
        }

        init(_ token: TokenEntry) {
            self.base = token
            self.coinGeckoId = token.coinGeckoId
            self.logoURL = token.logoURL
            add(token)
        }

        mutating func add(_ token: TokenEntry) {
            if coinGeckoId == nil {
                coinGeckoId = token.coinGeckoId
            }
            if logoURL == nil {
                logoURL = token.logoURL
            }

            if token.role.isBorrow {
                borrowAmount += token.amount
                borrowUSDValue += token.usdValue
            } else {
                positiveAmount += token.amount
                positiveUSDValue += token.usdValue
            }
        }
    }
}
