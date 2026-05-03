import SwiftUI

struct SettingsPage<Content: View>: View {
    let tab: SettingsTab
    let badge: SettingsBadge?
    private let content: Content

    init(
        tab: SettingsTab,
        badge: SettingsBadge? = nil,
        @ViewBuilder content: () -> Content) {
        self.tab = tab
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tab.title)
                            .font(.system(size: SettingsMetrics.pageTitleSize, weight: .bold))
                            .foregroundStyle(SettingsDesign.primaryText)
                        Text(tab.subtitle)
                            .font(.body)
                            .foregroundStyle(SettingsDesign.secondaryText)
                    }

                    Spacer(minLength: 24)

                    if let badge {
                        SettingsStatusBadge(badge: badge)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 34)

                content
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(SettingsDesign.contentBackground)
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    private let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: SettingsMetrics.sectionTitleSize, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.secondaryText)
            }

            SettingsDivider()

            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsDesign.cardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }
}

struct SettingsInfoCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                .foregroundStyle(SettingsDesign.primaryText)
            Text(message)
                .font(.footnote)
                .foregroundStyle(SettingsDesign.secondaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }
}

struct SettingsGlyphTile: View {
    let tab: SettingsTab
    var isSelected = false

    var body: some View {
        SettingsLetterTile(
            glyph: tab.sidebarGlyph,
            foreground: glyphColor,
            background: isSelected ? SettingsDesign.selectedGlyphBackground : glyphBackground)
    }

    private var glyphColor: Color {
        switch tab {
        case .general: SettingsDesign.accentBlue
        case .apiKeys: SettingsDesign.warningOrange
        case .debug: SettingsDesign.debugOrange
        }
    }

    private var glyphBackground: Color {
        switch tab {
        case .general: SettingsDesign.blueGlyphBackground
        case .apiKeys: SettingsDesign.orangeGlyphBackground
        case .debug: SettingsDesign.peachGlyphBackground
        }
    }
}

struct SettingsLetterTile: View {
    let glyph: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(glyph)
            .font(.caption.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.separator)
            .frame(height: 1)
    }
}

struct SettingsBadge: Equatable {
    enum Style: Equatable {
        case success
        case warning
    }

    let title: String
    let style: Style

    static let autoSave = SettingsBadge(title: "Auto-save", style: .success)
    static let debugOnly = SettingsBadge(title: "DEBUG only", style: .warning)
}

struct SettingsStatusBadge: View {
    let badge: SettingsBadge

    var body: some View {
        Text(badge.title)
            .font(.footnote.weight(.bold))
            .foregroundStyle(foreground)
            .frame(width: 132, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background))
    }

    private var background: Color {
        switch badge.style {
        case .success: SettingsDesign.successBadgeBackground
        case .warning: SettingsDesign.warningBadgeBackground
        }
    }

    private var foreground: Color {
        switch badge.style {
        case .success: SettingsDesign.successBadgeText
        case .warning: SettingsDesign.warningBadgeText
        }
    }
}

enum SettingsDesign {
    static let contentBackground = Color(red: 0.995, green: 0.997, blue: 1.0)
    static let sidebarBackground = Color(red: 0.945, green: 0.965, blue: 0.995)
    static let sidebarSearchBackground = Color(red: 0.905, green: 0.925, blue: 0.965)
    static let sidebarSelection = Color(red: 0.855, green: 0.895, blue: 1.0)
    static let cardBackground = Color.white
    static let subtleCardBackground = Color(red: 0.980, green: 0.988, blue: 0.998)
    static let separator = Color(red: 0.855, green: 0.875, blue: 0.910)
    static let cardStroke = Color(red: 0.800, green: 0.850, blue: 0.920)
    static let primaryText = Color(red: 0.045, green: 0.070, blue: 0.125)
    static let secondaryText = Color(red: 0.390, green: 0.440, blue: 0.560)
    static let accentBlue = Color(red: 0.055, green: 0.360, blue: 0.840)
    static let warningOrange = Color(red: 0.925, green: 0.250, blue: 0.050)
    static let debugOrange = Color(red: 0.830, green: 0.365, blue: 0.070)
    static let logoBackground = Color(red: 0.900, green: 0.925, blue: 1.0)
    static let logoForeground = Color(red: 0.340, green: 0.250, blue: 0.900)
    static let selectedGlyphBackground = Color.white
    static let blueGlyphBackground = Color(red: 0.930, green: 0.945, blue: 1.0)
    static let orangeGlyphBackground = Color(red: 1.0, green: 0.955, blue: 0.900)
    static let peachGlyphBackground = Color(red: 1.0, green: 0.940, blue: 0.895)
    static let successBadgeBackground = Color(red: 0.870, green: 0.965, blue: 0.925)
    static let successBadgeText = Color(red: 0.045, green: 0.415, blue: 0.275)
    static let warningBadgeBackground = Color(red: 1.0, green: 0.935, blue: 0.690)
    static let warningBadgeText = Color(red: 0.515, green: 0.205, blue: 0.010)
}
