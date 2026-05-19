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
            VStack(alignment: .leading, spacing: 14) {
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
                .padding(.top, 16)

                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: SettingsMetrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(SettingsDesign.contentBackground)
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: SettingsSectionIcon?
    private let content: Content

    init(
        title: String,
        subtitle: String,
        icon: SettingsSectionIcon? = nil,
        @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                if let icon {
                    let presentation = icon.presentation
                    SettingsIconTile(
                        systemImage: presentation.systemImage,
                        foreground: presentation.foreground,
                        background: presentation.background)
                        .frame(width: 30, height: 30)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: SettingsMetrics.sectionTitleSize, weight: .bold))
                        .foregroundStyle(SettingsDesign.primaryText)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
            }

            SettingsDivider()

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .fill(SettingsDesign.cardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }
}

struct SettingsGlyphTile: View {
    let tab: SettingsTab
    var isSelected = false

    var body: some View {
        let palette = tabPalette
        SettingsIconTile(
            systemImage: SettingsIconography.sidebarSystemImage(for: tab),
            foreground: palette.foreground,
            background: isSelected ? SettingsDesign.selectedGlyphBackground : palette.background)
    }

    private var tabPalette: (foreground: Color, background: Color) {
        switch tab {
        case .general: (SettingsDesign.accentPrimary, SettingsDesign.primaryGlyphBackground)
        case .tokens: (SettingsDesign.tokenTeal, SettingsDesign.tokenGlyphBackground)
        case .categories: (SettingsDesign.successBadgeText, SettingsDesign.successBadgeBackground)
        case .apiKeys: (SettingsDesign.warningOrange, SettingsDesign.orangeGlyphBackground)
        case .debug: (SettingsDesign.debugOrange, SettingsDesign.peachGlyphBackground)
        }
    }
}

struct SettingsIconTile: View {
    let systemImage: String
    let foreground: Color
    let background: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(background))
            .accessibilityHidden(true)
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
            .padding(.horizontal, 16)
            .frame(minWidth: 100, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
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

struct SettingsSwitchToggleStyle: ToggleStyle {
    let showsLabel: Bool

    init(showsLabel: Bool = true) {
        self.showsLabel = showsLabel
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                if showsLabel {
                    configuration.label
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SettingsDesign.primaryText)
                }

                switchControl(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }

    private func switchControl(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: SettingsDesign.switchTrackHeight / 2, style: .continuous)
            .fill(isOn ? SettingsDesign.accentPrimary.opacity(0.78) : SettingsDesign.disabledControlBackground)
            .frame(width: SettingsDesign.switchTrackWidth, height: SettingsDesign.switchTrackHeight)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.switchTrackHeight / 2, style: .continuous)
                    .strokeBorder(isOn ? SettingsDesign.accentPrimary.opacity(0.9) : SettingsDesign.cardStroke, lineWidth: 1))
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? SettingsDesign.primaryText : SettingsDesign.secondaryText)
                    .frame(width: SettingsDesign.switchThumbDiameter, height: SettingsDesign.switchThumbDiameter)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.24), radius: 2, x: 0, y: 1)
            }
            .animation(.spring(duration: SettingsDesign.switchAnimationDuration), value: isOn)
    }
}

struct SettingsSwitchRow: View {
    let title: String
    let subtitle: String
    @Binding private var isOn: Bool

    init(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            Toggle(title, isOn: $isOn)
                .settingsSwitchToggle(showsLabel: false)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: SettingsDesign.switchRowMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }
}

struct SettingsInlineNotice: View {
    enum Style {
        case error
        case action
    }

    let title: String
    let message: String?
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: message == nil ? 0 : 6) {
            Text(title)
                .font(.footnote.weight(.bold))
            if let message {
                Text(message)
                    .font(.footnote)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: message == nil ? 38 : 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .stroke(stroke, lineWidth: 1))
    }

    private var background: Color {
        switch style {
        case .error: Color(red: 0.190, green: 0.082, blue: 0.064)
        case .action: Color(red: 0.165, green: 0.135, blue: 0.082)
        }
    }

    private var stroke: Color {
        switch style {
        case .error: SettingsDesign.warningOrange.opacity(0.58)
        case .action: SettingsDesign.accentPrimary.opacity(0.58)
        }
    }

    private var foreground: Color {
        switch style {
        case .error: Color(red: 0.950, green: 0.535, blue: 0.390)
        case .action: SettingsDesign.primaryText
        }
    }
}

extension View {
    func settingsInputFrame(height: CGFloat) -> some View {
        padding(.horizontal, 12)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(SettingsDesign.subtleCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }

    func settingsMenuFrame(height: CGFloat) -> some View {
        padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(SettingsDesign.subtleCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }

    func settingsIconButton(color: Color) -> some View {
        foregroundStyle(color)
            .frame(width: 42, height: 28)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(color.opacity(0.10)))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 1))
    }

    func settingsPrimaryButton(isDisabled: Bool) -> some View {
        foregroundStyle(isDisabled ? SettingsDesign.secondaryText : SettingsDesign.primaryText)
            .font(.footnote.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, SettingsDesign.primaryButtonHorizontalPadding)
            .frame(minWidth: SettingsDesign.primaryButtonMinWidth)
            .frame(height: SettingsMetrics.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(isDisabled ? SettingsDesign.disabledControlBackground : SettingsDesign.accentPrimary.opacity(0.42)))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .strokeBorder(isDisabled ? SettingsDesign.cardStroke : SettingsDesign.accentPrimary.opacity(0.68), lineWidth: 1))
    }

    func settingsSecondaryButton(isDisabled: Bool) -> some View {
        foregroundStyle(isDisabled ? SettingsDesign.secondaryText : SettingsDesign.primaryText)
            .font(.footnote.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, SettingsDesign.primaryButtonHorizontalPadding)
            .frame(minWidth: SettingsDesign.primaryButtonMinWidth)
            .frame(height: SettingsMetrics.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .fill(isDisabled ? SettingsDesign.disabledControlBackground : SettingsDesign.subtleCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                    .strokeBorder(SettingsDesign.cardStroke, lineWidth: 1))
    }

    func settingsSwitchToggle(showsLabel: Bool = true) -> some View {
        toggleStyle(SettingsSwitchToggleStyle(showsLabel: showsLabel))
    }
}

enum SettingsDesign {
    static let panelCornerRadius: CGFloat = 8
    static let controlCornerRadius: CGFloat = 6
    static let switchTrackWidth: CGFloat = 42
    static let switchTrackHeight: CGFloat = 24
    static let switchThumbDiameter: CGFloat = 18
    static let switchRowMinHeight: CGFloat = 58
    static let switchAnimationDuration = 0.25
    static let primaryButtonMinWidth: CGFloat = 64
    static let primaryButtonHorizontalPadding: CGFloat = 16

    static let contentBackground = Color(red: 0.045, green: 0.043, blue: 0.039)
    static let sidebarBackground = Color(red: 0.110, green: 0.095, blue: 0.088)
    static let sidebarSearchBackground = Color(red: 0.105, green: 0.096, blue: 0.084)
    static let sidebarSelection = Color(red: 0.135, green: 0.123, blue: 0.108)
    static let cardBackground = Color(red: 0.072, green: 0.068, blue: 0.060)
    static let subtleCardBackground = Color(red: 0.105, green: 0.096, blue: 0.084)
    static let disabledControlBackground = Color(red: 0.090, green: 0.084, blue: 0.074)
    static let separator = Color(red: 0.178, green: 0.160, blue: 0.135)
    static let cardStroke = Color(red: 0.178, green: 0.160, blue: 0.135)
    static let primaryText = Color(red: 0.910, green: 0.885, blue: 0.820)
    static let secondaryText = Color(red: 0.610, green: 0.570, blue: 0.500)
    static let accentPrimary = Color(red: 0.690, green: 0.550, blue: 0.310)
    static let tokenTeal = Color(red: 0.260, green: 0.670, blue: 0.620)
    static let warningOrange = Color(red: 0.860, green: 0.330, blue: 0.330)
    static let debugOrange = Color(red: 0.850, green: 0.520, blue: 0.260)
    static let selectedGlyphBackground = Color(red: 0.360, green: 0.285, blue: 0.175)
    static let primaryGlyphBackground = Color(red: 0.190, green: 0.155, blue: 0.095)
    static let tokenGlyphBackground = Color(red: 0.105, green: 0.185, blue: 0.160)
    static let orangeGlyphBackground = Color(red: 0.220, green: 0.120, blue: 0.090)
    static let peachGlyphBackground = Color(red: 0.215, green: 0.145, blue: 0.090)
    static let successBadgeBackground = Color(red: 0.115, green: 0.215, blue: 0.145)
    static let successBadgeText = Color(red: 0.360, green: 0.730, blue: 0.455)
    static let warningBadgeBackground = Color(red: 0.255, green: 0.145, blue: 0.085)
    static let warningBadgeText = Color(red: 0.900, green: 0.600, blue: 0.250)
}
