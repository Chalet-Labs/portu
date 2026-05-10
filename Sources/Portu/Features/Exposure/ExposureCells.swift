import Foundation
import PortuCore
import PortuUI
import SwiftUI

struct ExposureSpotLiabilityCell<Row: ExposureRow>: View {
    let row: Row

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Text(ExposureFormat.currency(row.spotAssets, fractionDigits: 0))
                .foregroundStyle(PortuTheme.dashboardText)
            Text("/")
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
            Text(ExposureFormat.currency(-row.liabilities, fractionDigits: 0))
                .foregroundStyle(row.liabilities > 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardSecondaryText)
        }
        .font(DashboardStyle.monoTableFont)
    }
}

struct ExposureCurrencyCell: View {
    let value: Decimal
    let fractionDigits: Int

    var body: some View {
        Text(ExposureFormat.currency(value, fractionDigits: fractionDigits))
            .font(DashboardStyle.monoTableFont)
            .foregroundStyle(value < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardText)
    }
}

struct ExposureDerivativesCell: View {
    var body: some View {
        Text(ExposureFormat.placeholder)
            .font(DashboardStyle.monoTableFont)
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
    }
}

struct ExposureNetExposureCell<Row: ExposureRow>: View {
    let row: Row

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(ExposureFormat.currency(row.netExposure, fractionDigits: 2))
                .font(DashboardStyle.monoTableFont)
                .foregroundStyle(row.netExposure < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardGold)
                .lineLimit(1)
            Text(ExposureFormat.percent(row.shareOfSpot, fractionDigits: 1))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

struct ExposureAssetBadge: View {
    let symbol: String
    let logoURL: String?

    var body: some View {
        HStack(spacing: 7) {
            ExposureAssetLogo(symbol: symbol, logoURL: logoURL)
                .frame(width: 15, height: 15)

            Text(symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PortuTheme.dashboardMutedPanelBackground.opacity(0.78)))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ExposureAssetLogo: View {
    let symbol: String
    let logoURL: String?

    var body: some View {
        if let url = logoURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
            .clipShape(Circle())
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(PortuTheme.dashboardGoldMuted)
            Text(String(symbol.prefix(1)).uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(PortuTheme.dashboardGold)
        }
    }
}

struct ExposureCountPill: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(PortuTheme.dashboardText)
            Text("\(count)")
                .fontWeight(.bold)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PortuTheme.dashboardGoldMuted.opacity(0.45)))
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(PortuTheme.dashboardMutedPanelBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(PortuTheme.dashboardMutedStroke, lineWidth: 1))
    }
}

enum ExposureFormat {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static let placeholder = "—"

    static func currency(_ value: Decimal, fractionDigits: Int) -> String {
        let isNegative = value < 0
        let absoluteValue = isNegative ? -value : value
        let prefix = isNegative ? "- " : ""
        return "\(prefix)$ \(number(absoluteValue, fractionDigits: fractionDigits))"
    }

    static func percent(_ value: Decimal, fractionDigits: Int) -> String {
        let percentValue = NSDecimalNumber(decimal: value * 100).doubleValue
        return percentValue.formatted(.number
            .locale(locale)
            .grouping(.never)
            .precision(.fractionLength(fractionDigits))) + "%"
    }

    private static func number(_ value: Decimal, fractionDigits: Int) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number
            .locale(locale)
            .grouping(.automatic)
            .precision(.fractionLength(fractionDigits)))
    }
}
