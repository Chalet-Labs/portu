import Foundation

public enum PortfolioCategoryDefaults {
    public static let btcCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    public static let ethCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    public static let solCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    public static let defiCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    public static let memeCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
    public static let privacyCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
    public static let fiatCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
    public static let stablecoinsCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000108")!
    public static let fallbackCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000109")!

    public static let majorCategoryIDs: Set<UUID> = [
        btcCategoryID,
        ethCategoryID,
        solCategoryID
    ]

    public static let fallbackCategory = PortfolioCategorySnapshot(
        id: fallbackCategoryID,
        name: "Other Tokens",
        sortOrder: 8,
        semanticRole: .fallback,
        isSystemRequired: true)

    public static let categorySnapshots: [PortfolioCategorySnapshot] = [
        PortfolioCategorySnapshot(
            id: btcCategoryID,
            name: "BTC",
            sortOrder: 0,
            semanticRole: .normal,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: ethCategoryID,
            name: "ETH",
            sortOrder: 1,
            semanticRole: .normal,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: solCategoryID,
            name: "SOL",
            sortOrder: 2,
            semanticRole: .normal,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: defiCategoryID,
            name: "DeFi",
            sortOrder: 3,
            semanticRole: .normal,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: memeCategoryID,
            name: "Meme",
            sortOrder: 4,
            semanticRole: .normal,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: privacyCategoryID,
            name: "Privacy",
            sortOrder: 5,
            semanticRole: .normal,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: fiatCategoryID,
            name: "Fiat",
            sortOrder: 6,
            semanticRole: .fiat,
            isSystemRequired: false),
        PortfolioCategorySnapshot(
            id: stablecoinsCategoryID,
            name: "Stablecoins",
            sortOrder: 7,
            semanticRole: .stablecoin,
            isSystemRequired: false),
        fallbackCategory
    ]

    public static let symbolRuleSnapshots: [CategorySymbolRuleSnapshot] = [
        rule("BTC", categoryId: btcCategoryID),
        rule("WBTC", categoryId: btcCategoryID),
        rule("TBTC", categoryId: btcCategoryID),
        rule("CBBTC", categoryId: btcCategoryID),
        rule("ETH", categoryId: ethCategoryID),
        rule("WETH", categoryId: ethCategoryID),
        rule("STETH", categoryId: ethCategoryID),
        rule("WSTETH", categoryId: ethCategoryID),
        rule("RETH", categoryId: ethCategoryID),
        rule("CBETH", categoryId: ethCategoryID),
        rule("OSETH", categoryId: ethCategoryID),
        rule("SFRXETH", categoryId: ethCategoryID),
        rule("SOL", categoryId: solCategoryID),
        rule("WSOL", categoryId: solCategoryID),
        rule("MSOL", categoryId: solCategoryID),
        rule("JITOSOL", categoryId: solCategoryID),
        rule("JUPSOL", categoryId: solCategoryID),
        rule("USDC", categoryId: stablecoinsCategoryID),
        rule("USDC.E", categoryId: stablecoinsCategoryID),
        rule("USDT", categoryId: stablecoinsCategoryID),
        rule("DAI", categoryId: stablecoinsCategoryID),
        rule("USDS", categoryId: stablecoinsCategoryID),
        rule("FRAX", categoryId: stablecoinsCategoryID),
        rule("LUSD", categoryId: stablecoinsCategoryID),
        rule("PYUSD", categoryId: stablecoinsCategoryID),
        rule("GHO", categoryId: stablecoinsCategoryID),
        rule("FDUSD", categoryId: stablecoinsCategoryID),
        rule("TUSD", categoryId: stablecoinsCategoryID),
        rule("BUSD", categoryId: stablecoinsCategoryID),
        rule("USDD", categoryId: stablecoinsCategoryID),
        rule("USDE", categoryId: stablecoinsCategoryID),
        rule("CRVUSD", categoryId: stablecoinsCategoryID),
        rule("SUSD", categoryId: stablecoinsCategoryID)
    ]

    public static func normalizeSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    public static func legacyCategoryID(for category: AssetCategory) -> UUID {
        switch category {
        case .stablecoin:
            stablecoinsCategoryID
        case .defi:
            defiCategoryID
        case .meme:
            memeCategoryID
        case .privacy:
            privacyCategoryID
        case .fiat:
            fiatCategoryID
        case .major, .governance, .other:
            fallbackCategoryID
        }
    }

    private static func rule(_ symbol: String, categoryId: UUID) -> CategorySymbolRuleSnapshot {
        CategorySymbolRuleSnapshot(
            id: UUID(uuidString: deterministicRuleIDComponent(for: symbol))!,
            symbol: symbol,
            categoryId: categoryId)
    }

    private static let deterministicRuleIDs: [String: String] = [
        "BTC": "00000000-0000-0000-0000-000000000201",
        "WBTC": "00000000-0000-0000-0000-000000000202",
        "TBTC": "00000000-0000-0000-0000-000000000203",
        "CBBTC": "00000000-0000-0000-0000-000000000204",
        "ETH": "00000000-0000-0000-0000-000000000205",
        "WETH": "00000000-0000-0000-0000-000000000206",
        "STETH": "00000000-0000-0000-0000-000000000207",
        "WSTETH": "00000000-0000-0000-0000-000000000208",
        "RETH": "00000000-0000-0000-0000-000000000209",
        "CBETH": "00000000-0000-0000-0000-000000000210",
        "OSETH": "00000000-0000-0000-0000-000000000211",
        "SFRXETH": "00000000-0000-0000-0000-000000000212",
        "SOL": "00000000-0000-0000-0000-000000000213",
        "WSOL": "00000000-0000-0000-0000-000000000214",
        "MSOL": "00000000-0000-0000-0000-000000000215",
        "JITOSOL": "00000000-0000-0000-0000-000000000216",
        "JUPSOL": "00000000-0000-0000-0000-000000000217",
        "USDC": "00000000-0000-0000-0000-000000000218",
        "USDCE": "00000000-0000-0000-0000-000000000219",
        "USDT": "00000000-0000-0000-0000-000000000220",
        "DAI": "00000000-0000-0000-0000-000000000221",
        "USDS": "00000000-0000-0000-0000-000000000222",
        "FRAX": "00000000-0000-0000-0000-000000000223",
        "LUSD": "00000000-0000-0000-0000-000000000224",
        "PYUSD": "00000000-0000-0000-0000-000000000225",
        "GHO": "00000000-0000-0000-0000-000000000226",
        "FDUSD": "00000000-0000-0000-0000-000000000227",
        "TUSD": "00000000-0000-0000-0000-000000000228",
        "BUSD": "00000000-0000-0000-0000-000000000229",
        "USDD": "00000000-0000-0000-0000-000000000230",
        "USDE": "00000000-0000-0000-0000-000000000231",
        "CRVUSD": "00000000-0000-0000-0000-000000000232",
        "SUSD": "00000000-0000-0000-0000-000000000233"
    ]

    private static func deterministicRuleIDComponent(for symbol: String) -> String {
        let normalized = normalizeSymbol(symbol)
        return deterministicRuleIDs[normalized] ?? unknownDefaultRuleSymbol(symbol)
    }

    private static func unknownDefaultRuleSymbol(_ symbol: String) -> String {
        assertionFailure("Add a deterministic UUID for default symbol rule '\(symbol)'.")
        return "00000000-0000-0000-0000-000000000299"
    }
}

public struct PortfolioCategoryResolver: Equatable, Sendable {
    public let categories: [PortfolioCategorySnapshot]
    public let rules: [CategorySymbolRuleSnapshot]

    private let categoriesByID: [UUID: PortfolioCategorySnapshot]
    private let rulesBySymbol: [String: UUID]
    private let fallback: PortfolioCategorySnapshot

    public static let defaults = PortfolioCategoryResolver(
        categories: PortfolioCategoryDefaults.categorySnapshots,
        rules: PortfolioCategoryDefaults.symbolRuleSnapshots)

    public static func live(categories: [PortfolioCategory], rules: [CategorySymbolRule]) -> PortfolioCategoryResolver {
        guard !categories.isEmpty else { return .defaults }
        return PortfolioCategoryResolver(categories: categories, rules: rules)
    }

    public init(
        categories: [PortfolioCategorySnapshot],
        rules: [CategorySymbolRuleSnapshot]) {
        let sortedCategories = categories.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        let categoryMap = Dictionary(uniqueKeysWithValues: sortedCategories.map { ($0.id, $0) })
        var ruleMap: [String: UUID] = [:]
        var validRules: [CategorySymbolRuleSnapshot] = []

        for rule in rules.sorted(by: Self.sortRules) {
            let symbol = PortfolioCategoryDefaults.normalizeSymbol(rule.symbol)
            guard !symbol.isEmpty, categoryMap[rule.categoryId] != nil else { continue }
            ruleMap[symbol] = rule.categoryId
            validRules.append(CategorySymbolRuleSnapshot(id: rule.id, symbol: symbol, categoryId: rule.categoryId))
        }

        self.categories = sortedCategories
        self.rules = validRules
        self.categoriesByID = categoryMap
        self.rulesBySymbol = ruleMap
        self.fallback = sortedCategories.first { $0.semanticRole == .fallback }
            ?? categoryMap[PortfolioCategoryDefaults.fallbackCategoryID]
            ?? PortfolioCategoryDefaults.fallbackCategory
    }

    public init(categories: [PortfolioCategory], rules: [CategorySymbolRule]) {
        self.init(
            categories: categories.map(PortfolioCategorySnapshot.init),
            rules: rules.compactMap(CategorySymbolRuleSnapshot.init))
    }

    public func resolve(symbol: String, legacyCategory: AssetCategory) -> PortfolioCategorySnapshot {
        let normalized = PortfolioCategoryDefaults.normalizeSymbol(symbol)
        if
            let categoryId = rulesBySymbol[normalized],
            let category = categoriesByID[categoryId] {
            return category
        }

        let legacyCategoryID = PortfolioCategoryDefaults.legacyCategoryID(for: legacyCategory)
        return categoriesByID[legacyCategoryID] ?? fallback
    }

    public func isStablecoin(symbol: String, legacyCategory: AssetCategory) -> Bool {
        resolve(symbol: symbol, legacyCategory: legacyCategory).semanticRole == .stablecoin
    }

    private static func sortRules(
        _ lhs: CategorySymbolRuleSnapshot,
        _ rhs: CategorySymbolRuleSnapshot) -> Bool {
        if lhs.symbol != rhs.symbol {
            return lhs.symbol.localizedStandardCompare(rhs.symbol) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
