import PortuUI
import SwiftUI

enum AddAccountTab: Int, CaseIterable, Identifiable {
    case chain
    case manual
    case exchange

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .chain: "Chain account"
        case .manual: "Manual account"
        case .exchange: "Exchange account"
        }
    }
}

struct AddAccountTabSelector: View {
    @Binding var selection: AddAccountTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AddAccountTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selection == tab ? .medium : .regular))
                        .foregroundStyle(selection == tab ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == tab ? PortuTheme.dashboardGoldMuted : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PortuTheme.dashboardPanelElevatedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }
}

struct AddAccountSupportPanel: View {
    @Environment(\.openURL) private var openURL

    let title: String
    let chips: [AddAccountSupportChip.Model]
    let searchPlaceholder: String?
    let linkTitle: String
    var linkURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)

                FlowLayout(spacing: 5, rowSpacing: 5) {
                    ForEach(chips) { chip in
                        AddAccountSupportChip(model: chip)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    if let linkURL {
                        openURL(linkURL)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(linkTitle)
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
                .buttonStyle(.plain)
                .disabled(linkURL == nil)
                .help(linkURL == nil ? "Support documentation link is not configured yet." : "Open support documentation")
            }

            if let searchPlaceholder {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)

                    Text(searchPlaceholder)
                        .font(.system(size: 13))
                        .foregroundStyle(PortuTheme.dashboardTertiaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(PortuTheme.dashboardPanelBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
                .help("Live support lookup is not available yet.")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PortuTheme.dashboardPanelElevatedBackground.opacity(0.82)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PortuTheme.dashboardMutedStroke, lineWidth: 1))
    }
}

struct AddAccountSupportChip: View {
    struct Model: Identifiable {
        let title: String
        let systemImage: String?
        let tint: Color

        var id: String {
            "\(title)|\(systemImage ?? "")"
        }
    }

    let model: Model

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = model.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(model.tint))
            }

            Text(model.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(PortuTheme.dashboardText)
        .padding(.leading, model.systemImage == nil ? 7 : 5)
        .padding(.trailing, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PortuTheme.dashboardMutedPanelBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }
}

struct AddAccountManualInfoPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Manual Accounts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PortuTheme.dashboardText)

                Text("Use manual accounts to track positions you enter yourself, without connecting a wallet address or exchange API.")
                    .font(.system(size: 13))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Keep in mind")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PortuTheme.dashboardText)

                AddAccountInfoRow(
                    icon: "info.circle",
                    text: "Use it to track manual positions that do not map to existing accounts.")
                AddAccountInfoRow(
                    icon: "info.circle",
                    text: "For more info, read the full docs",
                    showsExternalLink: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PortuTheme.dashboardPanelElevatedBackground.opacity(0.78)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.62), lineWidth: 1))
    }
}

struct AddAccountKeepInMindPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Keep in mind")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PortuTheme.dashboardText)

            AddAccountInfoRow(
                icon: "exclamationmark.circle",
                iconColor: PortuTheme.dashboardGold,
                text: "Make sure to only add API keys with read-only permissions.")
            AddAccountInfoRow(
                icon: "exclamationmark.circle",
                iconColor: PortuTheme.dashboardGold,
                text: "If your exchange supports IP restrictions, follow the current setup guide before enabling them.")
            AddAccountInfoRow(
                icon: "info.circle",
                iconColor: PortuTheme.dashboardGold,
                text: "More info on how to get API keys. Read the docs",
                showsExternalLink: true)
        }
    }
}
