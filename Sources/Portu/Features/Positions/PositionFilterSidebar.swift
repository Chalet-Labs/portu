// Sources/Portu/Features/Positions/PositionFilterSidebar.swift
import PortuCore
import PortuUI
import SwiftUI

struct PositionFilterSidebar: View {
    let positions: [Position]
    @Binding var selectedType: PositionType?
    @Binding var selectedProtocol: ProtocolFilter

    private var typeFilters: [(PositionType?, String, Decimal)] {
        var result: [(PositionType?, String, Decimal)] = [
            (nil, "All", positions.reduce(Decimal.zero) { $0 + $1.netUSDValue })
        ]
        for type in PositionType.allCases {
            let matching = positions.filter { $0.positionType == type }
            guard !matching.isEmpty else { continue }
            let total = matching.reduce(Decimal.zero) { $0 + $1.netUSDValue }
            result.append((type, type.rawValue.capitalized, total))
        }
        return result
    }

    private var protocolFilters: [(id: String, name: String, value: Decimal)] {
        var byProtocol: [String: (name: String, value: Decimal)] = [:]
        for pos in positions {
            let id = pos.protocolId ?? "__none__"
            let name = pos.protocolName ?? "Wallet"
            var entry = byProtocol[id] ?? (name, 0)
            entry.value += pos.netUSDValue
            byProtocol[id] = entry
        }
        return byProtocol.map { (id: $0.key, name: $0.value.name, value: $0.value.value) }
            .sorted { $0.value > $1.value }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Position Type")
                        .font(DashboardStyle.labelFont)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    ForEach(typeFilters, id: \.1) { type, label, total in
                        Button {
                            selectedType = type
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundStyle(selectedType == type ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                                Spacer()
                                Text(total, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Rectangle()
                    .fill(PortuTheme.dashboardStroke)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Protocol")
                        .font(DashboardStyle.labelFont)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Button {
                        selectedProtocol = .all
                    } label: {
                        Text("All Protocols")
                            .foregroundStyle(selectedProtocol == .all ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                    }
                    .buttonStyle(.plain)

                    ForEach(protocolFilters, id: \.id) { filter in
                        let filterValue: ProtocolFilter = filter.id == "__none__" ? .none : .specific(filter.id)
                        Button {
                            selectedProtocol = filterValue
                        } label: {
                            HStack {
                                Text(filter.name)
                                    .foregroundStyle(selectedProtocol == filterValue ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                                Spacer()
                                Text(filter.value, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(PortuTheme.dashboardPanelBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(width: 1)
        }
    }
}
