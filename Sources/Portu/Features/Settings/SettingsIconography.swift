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

    static func sectionSystemImage(_ icon: SettingsSectionIcon) -> String {
        switch icon {
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

    static func visibilityToggleSystemImage(isVisible: Bool) -> String {
        isVisible ? "eye.slash" : "eye"
    }

    static func sectionForeground(_ icon: SettingsSectionIcon) -> Color {
        switch icon {
        case .priceUpdates, .tokenOverrides, .customRPCs: SettingsDesign.accentBlue
        case .dashboardVisibility: SettingsDesign.tokenTeal
        case .categoryRules, .createCategory: SettingsDesign.successBadgeText
        case .apiKeys: SettingsDesign.warningOrange
        case .debugServer, .launchArgument: SettingsDesign.debugOrange
        case .notices: SettingsDesign.warningBadgeText
        }
    }

    static func sectionBackground(_ icon: SettingsSectionIcon) -> Color {
        switch icon {
        case .priceUpdates, .tokenOverrides, .customRPCs: SettingsDesign.blueGlyphBackground
        case .dashboardVisibility: SettingsDesign.tokenGlyphBackground
        case .categoryRules, .createCategory: SettingsDesign.successBadgeBackground
        case .apiKeys: SettingsDesign.orangeGlyphBackground
        case .debugServer, .launchArgument: SettingsDesign.peachGlyphBackground
        case .notices: SettingsDesign.warningBadgeBackground
        }
    }
}
