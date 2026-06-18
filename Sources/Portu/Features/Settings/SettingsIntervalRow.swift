import SwiftUI

struct SettingsIntervalOption: Identifiable, Equatable {
    let seconds: Double
    let title: String

    var id: Double {
        seconds
    }
}

extension [SettingsIntervalOption] {
    static let coinGeckoLivePrices: Self = [
        SettingsIntervalOption(seconds: 30, title: "30 seconds"),
        SettingsIntervalOption(seconds: 60, title: "1 minute"),
        SettingsIntervalOption(seconds: 300, title: "5 minutes"),
        SettingsIntervalOption(seconds: 900, title: "15 minutes"),
        SettingsIntervalOption(seconds: 3600, title: "1 hour"),
        SettingsIntervalOption(seconds: 21600, title: "6 hours"),
        SettingsIntervalOption(seconds: 86400, title: "24 hours")
    ]

    static let zapperLivePriceFallback: Self = [
        SettingsIntervalOption(seconds: 0, title: "Manual only"),
        SettingsIntervalOption(seconds: 600, title: "10 minutes"),
        SettingsIntervalOption(seconds: 3600, title: "1 hour"),
        SettingsIntervalOption(seconds: 21600, title: "6 hours"),
        SettingsIntervalOption(seconds: 86400, title: "24 hours")
    ]

    static let zapperPortfolioSync: Self = [
        SettingsIntervalOption(seconds: 0, title: "Manual only"),
        SettingsIntervalOption(seconds: 3600, title: "1 hour"),
        SettingsIntervalOption(seconds: 21600, title: "6 hours"),
        SettingsIntervalOption(seconds: 86400, title: "24 hours")
    ]

    static let exchangePortfolioSync: Self = [
        SettingsIntervalOption(seconds: 0, title: "Manual only"),
        SettingsIntervalOption(seconds: 600, title: "10 minutes"),
        SettingsIntervalOption(seconds: 3600, title: "1 hour"),
        SettingsIntervalOption(seconds: 21600, title: "6 hours"),
        SettingsIntervalOption(seconds: 86400, title: "24 hours")
    ]
}

struct SettingsIntervalRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: Double
    let fallbackSeconds: Double
    let options: [SettingsIntervalOption]

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

            Menu {
                ForEach(options) { option in
                    if isSelected(option) {
                        Button {
                            selection = option.seconds
                        } label: {
                            Label(option.title, systemImage: "checkmark")
                        }
                    } else {
                        Button(option.title) {
                            selection = option.seconds
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SettingsDesign.primaryText)
                .padding(.horizontal, 12)
                .frame(minWidth: 128, minHeight: SettingsMetrics.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                        .fill(SettingsDesign.sidebarSearchBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                        .stroke(SettingsDesign.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
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

    private var selectedTitle: String {
        options.first { $0.seconds == selection }?.title
            ?? options.first { $0.seconds == fallbackSeconds }?.title
            ?? options.first?.title
            ?? ""
    }

    private func isSelected(_ option: SettingsIntervalOption) -> Bool {
        if options.contains(where: { $0.seconds == selection }) {
            return selection == option.seconds
        }
        return option.seconds == fallbackSeconds
    }
}
