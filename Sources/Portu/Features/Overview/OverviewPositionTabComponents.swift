import Foundation
import PortuCore
import PortuUI
import SwiftUI

struct OverviewPositionGroupData: Identifiable {
    let id: UUID
    let position: Position
    let tokens: [PositionToken]
}

struct TokenChangeCandidate {
    let token: PositionToken
    let position: Position
    let change: Decimal
}

enum OverviewPositionVisibility {
    static func isVisible(
        token: TokenEntry,
        prices: [String: Decimal],
        overrideMap: [UUID: TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings) -> Bool {
        TokenSettingsFeature.isDashboardEligible(
            token: token,
            prices: prices,
            override: overrideMap[token.assetId],
            settings: settings)
    }
}

struct OverviewPositionGroupCard: View {
    let group: OverviewPositionGroupData
    let price: (PositionToken) -> Decimal
    let tokenValue: (PositionToken) -> Decimal
    let tokenChange24h: (PositionToken) -> Decimal

    private var groupValue: Decimal {
        group.tokens.reduce(Decimal.zero) { partial, token in
            let value = tokenValue(token)
            return token.role.isBorrow ? partial - value : partial + value
        }
    }

    private var groupChange: Decimal {
        group.tokens.reduce(Decimal.zero) { partial, token in
            let change = tokenChange24h(token)
            return token.role.isBorrow ? partial - change : partial + change
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader

            VStack(spacing: 0) {
                columnHeader

                ForEach(group.tokens, id: \.id) { token in
                    OverviewPositionTokenRow(
                        token: token,
                        position: group.position,
                        price: price(token),
                        value: tokenValue(token),
                        change24h: tokenChange24h(token))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(PortuTheme.dashboardPanelElevatedBackground.opacity(0.65)))
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardGold)
                .frame(width: 18)

            Text(groupTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(OverviewPriceDisplay.currency(groupValue))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            Text(OverviewPriceDisplay.currency(groupChange))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(groupChange >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                .lineLimit(1)
        }
        .padding(.bottom, 8)
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("Position")
                .frame(width: 250, alignment: .leading)
            Text("Asset")
                .frame(width: 90, alignment: .leading)
            Text("Price / 24h")
                .frame(width: 140, alignment: .trailing)
            Text("Amount")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(PortuTheme.dashboardTertiaryText)
        .lineLimit(1)
        .padding(.bottom, 8)
    }

    private var groupTitle: String {
        group.position.protocolName ?? group.position.account?.name ?? "Wallet"
    }

    private var iconName: String {
        switch group.position.positionType {
        case .idle: "wallet.pass"
        case .lending: "building.columns"
        case .staking: "diamond"
        case .farming, .liquidityPool: "leaf"
        case .vesting: "clock"
        case .other: "square.grid.2x2"
        }
    }
}

private struct OverviewPositionTokenRow: View {
    let token: PositionToken
    let position: Position
    let price: Decimal
    let value: Decimal
    let change24h: Decimal

    var body: some View {
        HStack(spacing: 12) {
            positionContext
                .frame(width: 250, alignment: .leading)

            HStack(spacing: 7) {
                assetDot
                Text(token.asset?.symbol ?? "???")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .leading)

            HStack(spacing: 8) {
                Text(OverviewPriceDisplay.compactPrice(price))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.8)

                Text(OverviewPriceDisplay.currency(change24h))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OverviewPositionChangeTone.tone(for: token.role, change: change24h).color)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 140, alignment: .trailing)

            HStack(spacing: 8) {
                Text(OverviewPriceDisplay.amount(token.amount))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)

                if token.role.isBorrow {
                    Text("Close")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PortuTheme.dashboardWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PortuTheme.dashboardWarning.opacity(0.12)))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PortuTheme.dashboardWarning.opacity(0.55), lineWidth: 1))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 42)
    }

    private var positionContext: some View {
        HStack(spacing: 8) {
            Text(positionLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(roleColor)
                .lineLimit(1)

            if let chain = position.chain {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                    Text(chain.rawValue.capitalized)
                        .font(.system(size: 12))
                }
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
            }

            Text(token.role.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(PortuTheme.dashboardGoldMuted.opacity(0.35)))
        }
    }

    private var assetDot: some View {
        ZStack {
            Circle()
                .fill(PortuTheme.dashboardGoldMuted)
            Text(String((token.asset?.symbol ?? "?").prefix(1)))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(PortuTheme.dashboardText)
        }
        .frame(width: 16, height: 16)
    }

    private var positionLabel: String {
        switch position.positionType {
        case .idle: "Idle on"
        case .lending: "Lending on"
        case .staking: "Staked on"
        case .farming, .liquidityPool: "Yield on"
        case .vesting: "Vesting on"
        case .other: "Position on"
        }
    }

    private var roleColor: Color {
        token.role.isBorrow ? PortuTheme.dashboardWarning : PortuTheme.dashboardText
    }
}
