import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewPositionTabs: View {
    @Environment(AppState.self) private var appState
    @Query private var allPositions: [Position]

    @State private var selectedTab: OverviewTab = .keyChanges

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    enum OverviewTab: String, CaseIterable {
        case keyChanges = "Key Changes"
        case idleStables = "Idle Stables"
        case idleMajors = "Idle Majors"
        case borrowing = "Borrowing"
        case futures = "Futures"
        case options = "Options"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(OverviewTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 12) {
                switch selectedTab {
                case .keyChanges:
                    positionCards(tokens: keyChangeTokens, emptyTitle: "No key changes")
                case .idleStables:
                    positionCards(tokens: idleStableTokens, emptyTitle: "No idle stables")
                case .idleMajors:
                    positionCards(tokens: idleMajorTokens, emptyTitle: "No idle majors")
                case .borrowing:
                    borrowingView
                case .futures, .options:
                    emptyState("No deployed positions")
                }
            }
            .padding(14)
        }
    }

    private func tabButton(_ tab: OverviewTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedTab == tab ? PortuTheme.dashboardGold : .clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Token filtering

    private var allActiveTokens: [(PositionToken, Position)] {
        positions.flatMap { position in
            position.tokens.map { ($0, position) }
        }
    }

    private var keyChangeTokens: [(PositionToken, Position)] {
        allActiveTokens
            .filter(\.0.role.isPositive)
            .compactMap { token, position -> TokenChangeCandidate? in
                let change = tokenChange24h(token)
                guard change != 0 else { return nil }
                return TokenChangeCandidate(token: token, position: position, change: change)
            }
            .sorted {
                let lhs = abs($0.change)
                let rhs = abs($1.change)
                if lhs == rhs {
                    return ($0.token.asset?.symbol ?? "") < ($1.token.asset?.symbol ?? "")
                }
                return lhs > rhs
            }
            .prefix(20)
            .map { ($0.token, $0.position) }
    }

    private var idleStableTokens: [(PositionToken, Position)] {
        allActiveTokens
            .filter { $0.1.positionType == .idle && $0.0.asset?.category == .stablecoin && $0.0.role.isPositive }
    }

    private var idleMajorTokens: [(PositionToken, Position)] {
        allActiveTokens
            .filter { $0.1.positionType == .idle && $0.0.asset?.category == .major && $0.0.role.isPositive }
    }

    private func tokenChange24h(_ token: PositionToken) -> Decimal {
        OverviewPositionPricing.change24h(
            coinGeckoId: token.asset?.coinGeckoId,
            amount: token.amount,
            prices: appState.prices,
            changes24h: appState.priceChanges24h)
    }

    // MARK: - Position cards

    private func positionCards(
        tokens: [(PositionToken, Position)],
        emptyTitle: String) -> some View {
        Group {
            if tokens.isEmpty {
                emptyState(emptyTitle)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedTokens(tokens)) { group in
                        OverviewPositionGroupCard(
                            group: group,
                            price: price,
                            tokenValue: tokenValue,
                            tokenChange24h: tokenChange24h)
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardTertiaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    private func groupedTokens(_ tokens: [(PositionToken, Position)]) -> [OverviewPositionGroupData] {
        var order: [UUID] = []
        var grouped: [UUID: (position: Position, tokens: [PositionToken])] = [:]

        for (token, position) in tokens {
            if grouped[position.id] == nil {
                order.append(position.id)
                grouped[position.id] = (position, [])
            }
            grouped[position.id]?.tokens.append(token)
        }

        return order.compactMap { id in
            guard let group = grouped[id] else { return nil }
            return OverviewPositionGroupData(
                id: id,
                position: group.position,
                tokens: group.tokens)
        }
    }

    // MARK: - Borrowing

    @ViewBuilder
    private var borrowingView: some View {
        let borrowPositions = positions.filter { position in
            position.tokens.contains { $0.role.isBorrow }
        }

        if borrowPositions.isEmpty {
            emptyState("No borrowing")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(borrowPositions, id: \.id) { position in
                    OverviewPositionGroupCard(
                        group: OverviewPositionGroupData(
                            id: position.id,
                            position: position,
                            tokens: position.tokens.filter(\.role.isBorrow)),
                        price: price,
                        tokenValue: tokenValue,
                        tokenChange24h: tokenChange24h)
                }
            }
        }
    }

    // MARK: - Helpers

    private func price(_ token: PositionToken) -> Decimal {
        OverviewPositionPricing.price(
            coinGeckoId: token.asset?.coinGeckoId,
            amount: token.amount,
            usdValue: token.usdValue,
            prices: appState.prices)
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        OverviewPositionPricing.tokenValue(
            coinGeckoId: token.asset?.coinGeckoId,
            amount: token.amount,
            usdValue: token.usdValue,
            prices: appState.prices)
    }
}

private struct OverviewPositionGroupData: Identifiable {
    let id: UUID
    let position: Position
    let tokens: [PositionToken]
}

private struct TokenChangeCandidate {
    let token: PositionToken
    let position: Position
    let change: Decimal
}

private struct OverviewPositionGroupCard: View {
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

            Text(groupValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            Text(groupChange, format: .currency(code: "USD").precision(.fractionLength(0)))
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
                Text(price, format: .currency(code: "USD").precision(.fractionLength(0 ... 5)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardText)
                    .lineLimit(1)

                Text(change24h, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OverviewPositionChangeTone.tone(for: token.role, change: change24h).color)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .trailing)

            HStack(spacing: 8) {
                Text(token.amount, format: .number.precision(.fractionLength(2 ... 6)))
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
