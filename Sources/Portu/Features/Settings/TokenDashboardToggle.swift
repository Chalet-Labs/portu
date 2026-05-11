import Foundation

enum TokenDashboardTogglePresentation: Equatable {
    case inlineSettingRow
    case minimumValueInputAccessory
}

enum TokenDashboardToggle: CaseIterable, Equatable, Identifiable {
    case hideUnpriced
    case hideDust

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .hideUnpriced:
            TokenDashboardSettings.hideUnpricedTitle
        case .hideDust:
            TokenDashboardSettings.hideDustTitle
        }
    }

    var subtitle: String {
        switch self {
        case .hideUnpriced:
            "Exclude tokens without a resolved price from dashboard totals."
        case .hideDust:
            "Hide holdings below the configured minimum value."
        }
    }

    var presentation: TokenDashboardTogglePresentation {
        switch self {
        case .hideUnpriced:
            .inlineSettingRow
        case .hideDust:
            .minimumValueInputAccessory
        }
    }

    static var standaloneRows: [Self] {
        allCases.filter { $0.presentation == .inlineSettingRow }
    }
}
