import SwiftUI

struct HistoricalBackfillStatusRow: View {
    let status: HistoricalBackfillStatus

    var body: some View {
        let presentation = statusPresentation

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(presentation.foreground)
                .frame(width: 16, height: 16)

            Text(HistoricalBackfillStatusFormatter.message(for: status))
                .font(.footnote)
                .foregroundStyle(presentation.foreground)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .fill(presentation.background))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.controlCornerRadius, style: .continuous)
                .stroke(presentation.stroke, lineWidth: 1))
    }

    private var statusPresentation: HistoricalBackfillStatusPresentation {
        switch status {
        case .idle:
            HistoricalBackfillStatusPresentation(
                systemImage: "clock",
                foreground: SettingsDesign.secondaryText,
                background: SettingsDesign.subtleCardBackground,
                stroke: SettingsDesign.cardStroke)
        case .running, .clearing:
            HistoricalBackfillStatusPresentation(
                systemImage: "arrow.triangle.2.circlepath",
                foreground: SettingsDesign.primaryText,
                background: Color(red: 0.165, green: 0.135, blue: 0.082),
                stroke: SettingsDesign.accentPrimary.opacity(0.58))
        case let .succeeded(result) where !result.failedCoinGeckoIDs.isEmpty:
            HistoricalBackfillStatusPresentation(
                systemImage: "exclamationmark.triangle",
                foreground: SettingsDesign.warningBadgeText,
                background: SettingsDesign.warningBadgeBackground,
                stroke: SettingsDesign.warningBadgeText.opacity(0.50))
        case .succeeded:
            HistoricalBackfillStatusPresentation(
                systemImage: "checkmark.circle",
                foreground: SettingsDesign.successBadgeText,
                background: SettingsDesign.successBadgeBackground,
                stroke: SettingsDesign.successBadgeText.opacity(0.42))
        case .failed:
            HistoricalBackfillStatusPresentation(
                systemImage: "xmark.octagon",
                foreground: Color(red: 0.950, green: 0.535, blue: 0.390),
                background: Color(red: 0.190, green: 0.082, blue: 0.064),
                stroke: SettingsDesign.warningOrange.opacity(0.58))
        }
    }
}

private struct HistoricalBackfillStatusPresentation {
    let systemImage: String
    let foreground: Color
    let background: Color
    let stroke: Color
}
