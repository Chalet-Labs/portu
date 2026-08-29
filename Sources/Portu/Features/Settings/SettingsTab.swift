import Foundation

enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case app = "App"
    case sync = "Sync & Data"
    case portfolio = "Portfolio"
    case connections = "Connections"
    #if DEBUG
        case developer = "Developer"
    #endif

    var id: Self {
        self
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case updates
    case livePricesAndSync
    case historicalData
    case tokens
    case categories
    case apiKeys
    case debug

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "General"
        case .updates: "Updates"
        case .livePricesAndSync: "Live Prices & Sync"
        case .historicalData: "Historical Data"
        case .tokens: "Tokens"
        case .categories: "Categories"
        case .apiKeys: "API Keys"
        case .debug: "Debug"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Currency, price refresh, and general application preferences."
        case .updates: "Software update checks, release channels, and Sparkle status."
        case .livePricesAndSync: "Polling intervals for CoinGecko, Zerion, and exchange providers."
        case .historicalData: "Historical price cache backfill controls and status."
        case .tokens: "Manual pricing, low-value visibility, and token overrides."
        case .categories: "Category symbol rules for app-wide portfolio categories."
        case .apiKeys: "Provider credentials and optional custom RPC endpoints."
        case .debug: "Local debug server controls for development builds."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .updates: "arrow.down.circle"
        case .livePricesAndSync: "arrow.triangle.2.circlepath"
        case .historicalData: "chart.line.uptrend.xyaxis"
        case .tokens: "eye"
        case .categories: "tag"
        case .apiKeys: "key"
        case .debug: "wrench.and.screwdriver"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .general, .updates: .app
        case .livePricesAndSync, .historicalData: .sync
        case .tokens, .categories: .portfolio
        case .apiKeys: .connections
        case .debug:
            #if DEBUG
                .developer
            #else
                .connections
            #endif
        }
    }

    static func visibleTabs(debugEnabled: Bool) -> [SettingsTab] {
        debugEnabled
            ? [.general, .updates, .livePricesAndSync, .historicalData, .tokens, .categories, .apiKeys, .debug]
            : [.general, .updates, .livePricesAndSync, .historicalData, .tokens, .categories, .apiKeys]
    }

    static func filter(_ tabs: [SettingsTab], query: String) -> [SettingsTab] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return tabs }

        return tabs.filter { tab in
            tab.title.lowercased().contains(normalizedQuery)
                || tab.subtitle.lowercased().contains(normalizedQuery)
        }
    }
}

enum SettingsMetrics {
    static let minimumWidth: CGFloat = 860
    static let minimumHeight: CGFloat = 580
    static let sidebarWidth: CGFloat = 215
    static let pageMaxWidth: CGFloat = 960
    static let pageTitleSize: CGFloat = 22
    static let sectionTitleSize: CGFloat = 15
    static let rowTitleSize: CGFloat = 14
    static let sidebarRowTitleSize: CGFloat = 13
    static let sidebarHeaderTitle = "Settings"
    static let sidebarHeaderTitleSize: CGFloat = 28
    static let compactControlHeight: CGFloat = 32
    static let compactInputHeight: CGFloat = 32
    static let showsBackNavigation = false
}
