// Sources/Portu/Features/Positions/AllPositionsView.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AllPositionsView: View {
    @Query private var allPositions: [Position]

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    @State private var filterType: PositionType? = nil
    @State private var filterProtocol: ProtocolFilter = .all
    @State private var showAddSheet = false

    private var filteredPositions: [Position] {
        positions.filter { pos in
            if let ft = filterType, pos.positionType != ft { return false }
            if !filterProtocol.matches(pos.protocolId) { return false }
            return true
        }
    }

    /// Group positions: first by type, then by protocolId
    private var groupedByType: [(PositionType, [Position])] {
        Dictionary(grouping: filteredPositions, by: \.positionType)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                    DashboardPageHeader("All Positions") {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add Position", systemImage: "plus")
                        }
                        .dashboardControl()
                    }

                    ForEach(groupedByType, id: \.0) { type, positions in
                        Section {
                            ForEach(positions, id: \.id) { pos in
                                PositionGroupView(position: pos)
                            }
                        } header: {
                            HStack {
                                Text(typeSectionTitle(type))
                                    .font(DashboardStyle.sectionTitleFont)
                                    .foregroundStyle(PortuTheme.dashboardText)
                                Spacer()
                                let total = positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
                                Text(total, format: .currency(code: "USD"))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(DashboardStyle.pagePadding)
            }
            .frame(minWidth: 500)
            .sheet(isPresented: $showAddSheet) {
                AddPositionSheet()
                    .environment(\.colorScheme, .dark)
            }

            PositionFilterSidebar(
                positions: positions,
                selectedType: $filterType,
                selectedProtocol: $filterProtocol)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
        }
        .dashboardPage()
    }

    private func typeSectionTitle(_ type: PositionType) -> String {
        switch type {
        case .idle: "Idle"
        case .lending: "Lending"
        case .liquidityPool: "Liquidity Pools"
        case .staking: "Staking"
        case .farming: "Farming"
        case .vesting: "Vesting"
        case .other: "Other"
        }
    }
}
