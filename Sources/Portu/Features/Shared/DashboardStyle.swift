import PortuUI
import SwiftUI

enum DashboardStyle {
    static let pagePadding: CGFloat = 16
    static let panelPadding: CGFloat = 14
    static let compactPadding: CGFloat = 10

    static let pageTitleFont = Font.system(size: 18, weight: .semibold)
    static let heroValueFont = Font.system(size: 34, weight: .medium, design: .monospaced)
    static let sectionTitleFont = Font.system(size: 14, weight: .semibold)
    static let labelFont = Font.system(size: 11, weight: .medium)
    static let valueFont = Font.system(size: 13, weight: .semibold)
    static let tableFont = Font.system(size: 12)
    static let monoTableFont = Font.system(size: 12, design: .monospaced)
}

struct DashboardPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let actions: Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DashboardStyle.pageTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)
            actions
        }
    }
}

extension DashboardPageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actions = EmptyView()
    }
}

struct DashboardCard<Content: View>: View {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    private let content: Content

    init(
        horizontalPadding: CGFloat = DashboardStyle.panelPadding,
        verticalPadding: CGFloat = DashboardStyle.panelPadding,
        @ViewBuilder content: () -> Content) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: PortuTheme.dashboardPanelCornerRadius, style: .continuous)
                    .fill(PortuTheme.dashboardPanelBackground))
            .overlay(
                RoundedRectangle(cornerRadius: PortuTheme.dashboardPanelCornerRadius, style: .continuous)
                    .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }
}

struct DashboardMetricBlock: View {
    let title: String
    let value: String
    var subtitle: String?
    var valueColor: Color = PortuTheme.dashboardText

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(DashboardStyle.labelFont)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .textCase(.uppercase)
            Text(value)
                .font(DashboardStyle.valueFont)
                .foregroundStyle(valueColor)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
            }
        }
    }
}

struct DashboardSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct DashboardSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardText)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PortuTheme.dashboardPanelElevatedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }
}

extension View {
    func dashboardPage() -> some View {
        background(PortuTheme.dashboardBackground)
            .foregroundStyle(PortuTheme.dashboardText)
            .environment(\.colorScheme, .dark)
    }

    func dashboardCard(
        horizontalPadding: CGFloat = DashboardStyle.panelPadding,
        verticalPadding: CGFloat = DashboardStyle.panelPadding) -> some View {
        DashboardCard(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding) {
                self
            }
    }

    func dashboardControl() -> some View {
        controlSize(.small)
            .tint(PortuTheme.dashboardGold)
    }

    func dashboardTable() -> some View {
        font(DashboardStyle.tableFont)
            .controlSize(.small)
            .tint(PortuTheme.dashboardGold)
            .environment(\.defaultMinListRowHeight, PortuTheme.dashboardTableRowHeight)
            .background(PortuTheme.dashboardPanelBackground)
    }
}
