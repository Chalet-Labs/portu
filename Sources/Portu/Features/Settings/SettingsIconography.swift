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
        switch self {
        case .priceUpdates, .tokenOverrides, .customRPCs:
            SettingsSectionIconPresentation(
                systemImage: systemImage,
                foreground: SettingsDesign.accentPrimary,
                background: SettingsDesign.primaryGlyphBackground)
        case .dashboardVisibility:
            SettingsSectionIconPresentation(
                systemImage: systemImage,
                foreground: SettingsDesign.tokenTeal,
                background: SettingsDesign.tokenGlyphBackground)
        case .categoryRules, .createCategory:
            SettingsSectionIconPresentation(
                systemImage: systemImage,
                foreground: SettingsDesign.successBadgeText,
                background: SettingsDesign.successBadgeBackground)
        case .apiKeys:
            SettingsSectionIconPresentation(
                systemImage: systemImage,
                foreground: SettingsDesign.warningOrange,
                background: SettingsDesign.orangeGlyphBackground)
        case .debugServer, .launchArgument:
            SettingsSectionIconPresentation(
                systemImage: systemImage,
                foreground: SettingsDesign.debugOrange,
                background: SettingsDesign.peachGlyphBackground)
        case .notices:
            SettingsSectionIconPresentation(
                systemImage: systemImage,
                foreground: SettingsDesign.warningBadgeText,
                background: SettingsDesign.warningBadgeBackground)
        }
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
