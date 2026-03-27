import SwiftUI
import PortuUI

struct PositionFilterSidebar: View {
    struct Snapshot: Equatable {
        struct PositionTypeRow: Equatable, Identifiable {
            let filter: PositionFilter
            let title: String
            let total: Decimal
            let isSelected: Bool

            var id: PositionFilter {
                filter
            }
        }

        struct ProtocolRow: Equatable, Identifiable {
            let title: String
            let isSelected: Bool

            var id: String {
                title
            }
        }

        let positionTypeRows: [PositionTypeRow]
        let protocolRows: [ProtocolRow]
    }

    static let positionTypesSectionTitle = "Position Types"
    static let protocolsSectionTitle = "Protocols"
    static let defaultProtocolOptionTitle = "All Protocols"

    @Binding var selectedPositionFilter: PositionFilter
    @Binding var selectedProtocol: String?

    let positionFilterTotals: [PositionFilter: Decimal]
    let protocolOptions: [String]

    static func makeSnapshot(
        selectedPositionFilter: PositionFilter,
        selectedProtocol: String?,
        positionFilterTotals: [PositionFilter: Decimal],
        protocolOptions: [String]
    ) -> Snapshot {
        let positionTypeRows = PositionFilter.allCases.map { filter in
            Snapshot.PositionTypeRow(
                filter: filter,
                title: filter.title,
                total: positionFilterTotals[filter] ?? .zero,
                isSelected: selectedPositionFilter == filter
            )
        }

        let protocolRows = [
            Snapshot.ProtocolRow(
                title: defaultProtocolOptionTitle,
                isSelected: selectedProtocol == nil
            )
        ] + protocolOptions.map { option in
            Snapshot.ProtocolRow(
                title: option,
                isSelected: selectedProtocol == option
            )
        }

        return Snapshot(
            positionTypeRows: positionTypeRows,
            protocolRows: protocolRows
        )
    }

    var body: some View {
        let snapshot = Self.makeSnapshot(
            selectedPositionFilter: selectedPositionFilter,
            selectedProtocol: selectedProtocol,
            positionFilterTotals: positionFilterTotals,
            protocolOptions: protocolOptions
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        Self.positionTypesSectionTitle,
                        subtitle: "USD totals across active positions"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.positionTypeRows) { row in
                            filterButton(
                                title: row.title,
                                value: row.total,
                                isSelected: row.isSelected
                            ) {
                                selectedPositionFilter = row.filter
                            }
                        }
                    }
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        Self.protocolsSectionTitle,
                        subtitle: "Select a protocol to narrow the workspace"
                    )

                    if protocolOptions.isEmpty {
                        ContentUnavailableView {
                            Label("No Protocols", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("Choose a different position type to reveal protocol options.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(snapshot.protocolRows) { row in
                                protocolButton(
                                    title: row.title,
                                    isSelected: row.isSelected
                                ) {
                                    selectedProtocol = row.title == Self.defaultProtocolOptionTitle ? nil : row.title
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SectionHeader(
                "Workspace Filters",
                subtitle: "Type filters, protocol drill-down, and manual entry"
            )

            Spacer(minLength: 0)

            ManualPositionButton()
        }
    }

    private func filterButton(
        title: String,
        value: Decimal,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))

                    CurrencyText(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func protocolButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
            )
        }
        .buttonStyle(.plain)
    }
}
