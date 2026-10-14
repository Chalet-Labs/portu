import PortuCore
import PortuUI
import SwiftUI

enum OverviewHistoricalPriceChangeFeature {}

enum OverviewPositionChangeTone: Equatable {
    case favorable
    case unfavorable

    static func tone(for role: TokenRole, change: Decimal) -> OverviewPositionChangeTone {
        tone(isDebt: role.isBorrow, change: change)
    }

    static func tone(isDebt: Bool, change: Decimal) -> OverviewPositionChangeTone {
        if isDebt {
            return change <= 0 ? .favorable : .unfavorable
        }
        return change >= 0 ? .favorable : .unfavorable
    }

    @MainActor
    var color: Color {
        switch self {
        case .favorable:
            PortuTheme.dashboardSuccess
        case .unfavorable:
            PortuTheme.dashboardWarning
        }
    }
}
