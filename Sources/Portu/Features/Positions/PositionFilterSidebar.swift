// Sources/Portu/Features/Positions/PositionFilterSidebar.swift
import PortuCore
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
                    .font(.headline)

                // Type filter
                Section("Position Type") {
                    ForEach(typeFilters, id: \.1) { type, label, total in
                        Button {
                            selectedType = type
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundStyle(selectedType == type ? .primary : .secondary)
                                Spacer()
                                Text(total, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Protocol filter (uses protocolId to match AllPositionsView filtering)
                Section("Protocol") {
                    Button {
                        selectedProtocol = .all
                    } label: {
                        Text("All Protocols")
                            .foregroundStyle(selectedProtocol == .all ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    ForEach(protocolFilters, id: \.id) { filter in
                        let filterValue: ProtocolFilter = filter.id == "__none__" ? .none : .specific(filter.id)
                        Button {
                            selectedProtocol = filterValue
                        } label: {
                            HStack {
                                Text(filter.name)
                                    .foregroundStyle(selectedProtocol == filterValue ? .primary : .secondary)
                                Spacer()
                                Text(filter.value, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}
