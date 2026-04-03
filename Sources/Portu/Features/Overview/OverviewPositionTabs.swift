// Sources/Portu/Features/Overview/OverviewPositionTabs.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewPositionTabs: View {
    @Environment(AppState.self) private var appState
    @Query private var allPositions: [Position]

    @State private var selectedTab: OverviewTab = .keyChanges

    /// Only positions from active accounts
    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    enum OverviewTab: String, CaseIterable {
        case keyChanges = "Key Changes"
        case idleStables = "Idle Stables"
        case idleMajors = "Idle Majors"
        case borrowing = "Borrowing"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(OverviewTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .keyChanges:
                tokenTable(tokens: keyChangeTokens)
            case .idleStables:
                tokenTable(tokens: idleStableTokens)
            case .idleMajors:
                tokenTable(tokens: idleMajorTokens)
            case .borrowing:
                borrowingView
            }
        }
    }

    // MARK: - Token filtering

    private var allActiveTokens: [(PositionToken, Position)] {
        positions.flatMap { pos in pos.tokens.map { ($0, pos) } }
    }

    private var keyChangeTokens: [(PositionToken, Position)] {
        // Tokens with largest 24h USD change (absolute value), excluding those without 24h data
        allActiveTokens
            .filter(\.0.role.isPositive)
            .filter { tokenChange24h($0.0) != 0 }
            .sorted { abs(tokenChange24h($0.0)) > abs(tokenChange24h($1.0)) }
            .prefix(20)
            .map { ($0.0, $0.1) }
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
        guard
            let cgId = token.asset?.coinGeckoId,
            let price = appState.prices[cgId],
            let changePct = appState.priceChanges24h[cgId] else { return 0 }
        return token.amount * price * changePct
    }

    // MARK: - Token table (flat rows)

    private func tokenTable(tokens: [(PositionToken, Position)]) -> some View {
        Table(of: TokenRowData.self) {
            TableColumn("Asset") { row in
                Text(row.symbol).fontWeight(.medium)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Network / Account") { row in
                VStack(alignment: .leading) {
                    if let chain = row.chain { Text(chain.rawValue.capitalized).font(.caption) }
                    Text(row.accountName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("Amount") { row in
                Text(row.amount, format: .number.precision(.fractionLength(2 ... 6)))
            }
            .width(min: 80, ideal: 100)

            TableColumn("Price") { row in
                Text(row.price, format: .currency(code: "USD"))
            }
            .width(min: 60, ideal: 80)

            TableColumn("Value") { row in
                Text(row.value, format: .currency(code: "USD"))
            }
            .width(min: 80, ideal: 100)
        } rows: {
            ForEach(tokens.map { makeTokenRowData($0.0, position: $0.1) }, id: \.id) { row in
                TableRow(row)
            }
        }
    }

    // MARK: - Borrowing view (grouped by protocol)

    @ViewBuilder
    private var borrowingView: some View {
        let borrowPositions = positions.filter { pos in
            pos.tokens.contains { $0.role.isBorrow }
        }
        if borrowPositions.isEmpty {
            ContentUnavailableView(
                "No Borrowing",
                systemImage: "arrow.down.circle",
                description: Text("No active borrow positions"))
        } else {
            ForEach(borrowPositions, id: \.id) { pos in
                VStack(alignment: .leading, spacing: 4) {
                    // Section header
                    HStack {
                        Text(pos.protocolName ?? "Unknown Protocol")
                            .font(.headline)
                        if let chain = pos.chain {
                            CapsuleBadge(chain.rawValue.capitalized)
                        }
                        Spacer()
                        if let hf = pos.healthFactor {
                            Text("HF: \(hf, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundStyle(hf < 1.2 ? .red : hf < 1.5 ? .orange : .green)
                        }
                    }

                    // Token rows
                    ForEach(pos.tokens, id: \.id) { token in
                        HStack {
                            Text(token.role.displayLabel)
                                .font(.caption)
                                .foregroundStyle(token.role.displayColor)
                            Text(token.asset?.symbol ?? "???")
                            Spacer()
                            Text(token.amount, format: .number.precision(.fractionLength(2 ... 6)))
                            Text(tokenValue(token), format: .currency(code: "USD"))
                                .frame(width: 100, alignment: .trailing)
                        }
                        .font(.body)
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Helpers

    private struct TokenRowData: Identifiable {
        let id: UUID
        let symbol: String
        let chain: Chain?
        let accountName: String
        let amount: Decimal
        let price: Decimal
        let value: Decimal
    }

    private func makeTokenRowData(_ token: PositionToken, position: Position) -> TokenRowData {
        let price = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }
            ?? (token.amount > 0 ? token.usdValue / token.amount : 0)
        let value = token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue

        return TokenRowData(
            id: token.id,
            symbol: token.asset?.symbol ?? "???",
            chain: position.chain,
            accountName: position.account?.name ?? "",
            amount: token.amount,
            price: price,
            value: value)
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        token.resolvedUSDValue(prices: appState.prices)
    }
}
