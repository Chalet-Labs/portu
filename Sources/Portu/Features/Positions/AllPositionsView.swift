// Sources/Portu/Features/Positions/AllPositionsView.swift
import SwiftUI
import SwiftData
import PortuCore

struct AllPositionsView: View {
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    @State private var filterType: PositionType? = nil
    @State private var filterProtocol: String? = nil
    @State private var showAddSheet = false

    private var filteredPositions: [Position] {
        positions.filter { pos in
            if let ft = filterType, pos.positionType != ft { return false }
            if let fp = filterProtocol, pos.protocolId != fp { return false }
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
            // Main content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedByType, id: \.0) { (type, positions) in
                        Section {
                            ForEach(positions, id: \.id) { pos in
                                PositionGroupView(position: pos)
                            }
                        } header: {
                            HStack {
                                Text(typeSectionTitle(type))
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                let total = positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
                                Text(total, format: .currency(code: "USD"))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 500)
            .toolbar {
                ToolbarItem {
                    Button("Add Position", systemImage: "plus") {
                        showAddSheet = true
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPositionSheet()
            }

            // Filter sidebar
            PositionFilterSidebar(
                positions: positions,
                selectedType: $filterType,
                selectedProtocol: $filterProtocol
            )
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
        }
        .navigationTitle("All Positions")
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
