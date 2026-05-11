import SwiftUI

enum SettingsSectionIcon: Equatable {
    case priceUpdates
    case dashboardVisibility
    case tokenOverrides
    case categoryRules
    case createCategory
    case apiKeys
    case customRPCs
    case debugServer
    case notices
    case launchArgument

    var presentation: SettingsSectionIconPresentation {
        let palette: (foreground: Color, background: Color) = switch self {
        case .priceUpdates, .tokenOverrides, .customRPCs:
            (SettingsDesign.accentPrimary, SettingsDesign.primaryGlyphBackground)
        case .dashboardVisibility:
            (SettingsDesign.tokenTeal, SettingsDesign.tokenGlyphBackground)
        case .categoryRules, .createCategory:
            (SettingsDesign.successBadgeText, SettingsDesign.successBadgeBackground)
        case .apiKeys:
            (SettingsDesign.warningOrange, SettingsDesign.orangeGlyphBackground)
        case .debugServer, .launchArgument:
            (SettingsDesign.debugOrange, SettingsDesign.peachGlyphBackground)
        case .notices:
            (SettingsDesign.warningBadgeText, SettingsDesign.warningBadgeBackground)
        }
        return SettingsSectionIconPresentation(
            systemImage: systemImage,
            foreground: palette.foreground,
            background: palette.background)
    }

    var systemImage: String {
        switch self {
        case .priceUpdates: "arrow.clockwise"
        case .dashboardVisibility: "eye"
        case .tokenOverrides: "slider.horizontal.3"
        case .categoryRules: "tag"
        case .createCategory: "plus"
        case .apiKeys: "key"
        case .customRPCs: "network"
        case .debugServer: "wrench.and.screwdriver"
        case .notices: "bell"
        case .launchArgument: "terminal"
        }
    }
}

struct SettingsSectionIconPresentation: Equatable {
    let systemImage: String
    let foreground: Color
    let background: Color
}

enum SettingsIconography {
    static let apiKeyFieldSystemImage = "key"

    static func sidebarSystemImage(for tab: SettingsTab) -> String {
        switch tab {
        case .general: "gearshape"
        case .tokens: "eye"
        case .categories: "tag"
        case .apiKeys: "key"
        case .debug: "wrench.and.screwdriver"
        }
    }

    static func visibilityToggleSystemImage(isVisible: Bool) -> String {
        isVisible ? "eye.slash" : "eye"
    }
}
