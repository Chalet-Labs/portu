struct SidebarLayoutSection: Equatable, Identifiable {
    let id: String
    let title: String?
    let items: [SidebarItem]
    let isDisabled: Bool

    init(
        title: String?,
        items: [SidebarItem],
        isDisabled: Bool = false) {
        self.title = title
        self.items = items
        self.isDisabled = isDisabled
        self.id = title ?? items.map(\.id).joined(separator: "-")
    }
}

enum SidebarItem: Equatable, Identifiable {
    case section(SidebarSection)
    case strategies
    case settings

    var id: String {
        switch self {
        case let .section(section): "section-\(section.id)"
        case .strategies: "strategies"
        case .settings: "settings"
        }
    }
}

enum SidebarLayout {
    static let navigationSections: [SidebarLayoutSection] = [
        SidebarLayoutSection(
            title: "PORTU",
            items: [
                .section(.overview),
                .section(.exposure),
                .section(.performance)
            ]),
        SidebarLayoutSection(
            title: "PORTFOLIO",
            items: [
                .section(.allAssets),
                .section(.allPositions)
            ]),
        SidebarLayoutSection(
            title: "MANAGEMENT",
            items: [
                .section(.accounts)
            ]),
        SidebarLayoutSection(
            title: nil,
            items: [.strategies],
            isDisabled: true)
    ]

    static let footerItems: [SidebarItem] = [.settings]
}

extension SidebarSection {
    var id: String {
        switch self {
        case .overview: "overview"
        case .exposure: "exposure"
        case .performance: "performance"
        case .allAssets: "all-assets"
        case .allPositions: "all-positions"
        case .accounts: "accounts"
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .exposure: "Exposure"
        case .performance: "Performance"
        case .allAssets: "All Assets"
        case .allPositions: "All Positions"
        case .accounts: "Accounts"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "chart.pie"
        case .exposure: "chart.bar.xaxis"
        case .performance: "chart.line.uptrend.xyaxis"
        case .allAssets: "bitcoinsign.circle"
        case .allPositions: "list.bullet.rectangle"
        case .accounts: "person.2"
        }
    }
}
