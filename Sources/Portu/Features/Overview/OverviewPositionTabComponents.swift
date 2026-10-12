import Foundation
import PortuCore
import PortuUI
import SwiftUI

/// Position-level presentation data, projected from a `Position` once per render pass.
///
/// Holds no SwiftData references. A sync can delete and reinsert the underlying
/// `Position` while SwiftUI is still evaluating a body; reading a deleted model's
/// properties trips a SwiftData assertion and terminates the process, so views
/// downstream of this projection must never see a `@Model` instance.
struct OverviewPositionMeta: Identifiable, Equatable {
    let id: UUID
    let title: String
    let positionType: PositionType
    let chain: Chain?

    var iconName: String {
        switch positionType {
        case .idle: "wallet.pass"
        case .lending: "building.columns"
        case .staking: "diamond"
        case .farming, .liquidityPool: "leaf"
        case .vesting: "clock"
        case .other: "square.grid.2x2"
        }
    }

    /// Row prefix describing how the asset is deployed, e.g. "Staked on".
    var contextLabel: String {
        switch positionType {
        case .idle: "Idle on"
        case .lending: "Lending on"
        case .staking: "Staked on"
        case .farming, .liquidityPool: "Yield on"
        case .vesting: "Vesting on"
        case .other: "Position on"
        }
    }
}

/// Token-level presentation data with pricing already resolved.
///
/// Pricing is resolved by `OverviewPositionProjection` rather than re-derived per row
/// by view closures. Both the crash safety and the cost saving come from the same
/// property: nothing here needs to be recomputed while a body is being evaluated.
/// `value` and `change24h` are on the tab's basis: a borrow row shows its debt, and its change is
/// positive when the debt grows.
struct OverviewPositionTokenData: Identifiable, Equatable {
    let id: UUID
    let entry: TokenEntry
    let price: Decimal
    let value: Decimal
    let change24h: Decimal

    var role: TokenRole {
        entry.role
    }

    var symbol: String {
        entry.symbol
    }

    var logoURL: String? {
        entry.logoURL
    }

    var amount: Decimal {
        entry.amount
    }
}

/// A position and its qualifying tokens, ready to render. The group's list ends with its own
/// hidden-balances line (F3), so its total and 24h change cover the hidden rows too. Both are on
/// the tab's basis: gross for the holding tabs, positive debt for Borrowing (S3).
struct OverviewPositionGroupData: Identifiable, Equatable {
    let position: OverviewPositionMeta
    let tokens: [OverviewPositionTokenData]
    var basis: DashboardBasis = .gross
    /// The group's rows the display filter hides, in the display currency; `nil` when none are.
    var hidden: HiddenBalances?
    /// The hidden rows' 24h change, on the group's basis.
    var hiddenChange24h: Decimal = 0

    var id: UUID {
        position.id
    }

    /// Σ visible rows + the hidden line.
    var value: Decimal {
        tokens.reduce(.zero) { $0 + $1.value } + (hidden?.value(on: basis) ?? 0)
    }

    var change24h: Decimal {
        tokens.reduce(.zero) { $0 + $1.change24h } + hiddenChange24h
    }

    /// A growing debt is a loss.
    var changeTone: OverviewPositionChangeTone {
        OverviewPositionChangeTone.tone(isDebt: basis == .debt, change: change24h)
    }
}

enum OverviewPositionVisibility {
    static func isVisible(
        token: TokenEntry,
        prices: [String: Decimal],
        overrideMap: [UUID: TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings,
        usdToDisplayRate: Decimal = 1) -> Bool {
        TokenSettingsFeature.isDashboardEligible(
            token: token,
            prices: prices,
            override: overrideMap[token.assetId],
            settings: settings,
            usdToDisplayRate: usdToDisplayRate)
    }
}

struct OverviewPositionGroupCard: View {
    let group: OverviewPositionGroupData
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader

            VStack(spacing: 0) {
                columnHeader

                ForEach(group.tokens) { token in
                    OverviewPositionTokenRow(
                        token: token,
                        position: group.position,
                        currencyCode: currencyCode)
                }

                if let hidden = group.hidden {
                    OverviewHiddenBalancesLine(
                        text: OverviewPriceDisplay.hiddenBalancesLine(hidden, basis: group.basis, currencyCode: currencyCode))
                }
            }
            .overviewPositionPanel()
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: group.position.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardGold)
                .frame(width: 18)

            Text(group.position.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(OverviewPriceDisplay.currency(group.value, currencyCode: currencyCode))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            Text(OverviewPriceDisplay.currency(group.change24h, currencyCode: currencyCode))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(group.changeTone.color)
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
}

/// The hidden-balances line (F3) that ends a position list.
struct OverviewHiddenBalancesLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11))
                .foregroundStyle(PortuTheme.dashboardTertiaryText)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }
}

extension View {
    /// The elevated panel a position group's rows sit on.
    @MainActor
    func overviewPositionPanel() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(PortuTheme.dashboardPanelElevatedBackground.opacity(0.65)))
    }
}

private struct OverviewPositionTokenRow: View {
    let token: OverviewPositionTokenData
    let position: OverviewPositionMeta
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            positionContext
                .frame(width: 250, alignment: .leading)

            HStack(spacing: 7) {
                AssetLogoView(symbol: token.symbol, logoURL: token.logoURL)
                    .frame(width: 16, height: 16)
                Text(token.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .leading)

            HStack(spacing: 8) {
                Text(OverviewPriceDisplay.compactPrice(token.price, currencyCode: currencyCode))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.8)

                Text(OverviewPriceDisplay.currency(token.change24h, currencyCode: currencyCode))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OverviewPositionChangeTone.tone(for: token.role, change: token.change24h).color)
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
            Text(position.contextLabel)
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

    private var roleColor: Color {
        token.role.isBorrow ? PortuTheme.dashboardWarning : PortuTheme.dashboardText
    }
}
