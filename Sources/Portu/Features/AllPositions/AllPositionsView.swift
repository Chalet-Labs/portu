import SwiftData
import SwiftUI
import PortuCore
import PortuUI

struct AllPositionsView: View {
    static let navigationTitle = "All Positions"

    @Query private var positions: [Position]
    @State private var selectedPositionFilter: PositionFilter = .all
    @State private var selectedProtocol: String?

    private var activePositions: [Position] {
        positions.filter { $0.account?.isActive == true }
    }

    private var positionsMatchingTypeFilter: [Position] {
        activePositions.filter { selectedPositionFilter.matches($0) }
    }

    private var positionsMatchingAllFilters: [Position] {
        positionsMatchingTypeFilter.filter { position in
            guard let selectedProtocol else {
                return true
            }

            return protocolDisplayName(for: position) == selectedProtocol
        }
    }

    private var contentViewModel: AllPositionsViewModel {
        AllPositionsViewModel(positions: positionsMatchingAllFilters)
    }

    private var sidebarProtocolOptions: [String] {
        AllPositionsViewModel(positions: positionsMatchingTypeFilter).protocolOptions
    }

    private var positionFilterTotals: [PositionFilter: Decimal] {
        Dictionary(
            uniqueKeysWithValues: PositionFilter.allCases.map { filter in
                (
                    filter,
                    activePositions.filter { filter.matches($0) }.reduce(.zero) { $0 + $1.netUSDValue }
                )
            }
        )
    }

    var body: some View {
        let workspaceViewModel = contentViewModel
        let availableProtocolOptions = sidebarProtocolOptions

        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if workspaceViewModel.sections.isEmpty {
                        ContentUnavailableView {
                            Label(emptyStateTitle, systemImage: "tray.full")
                        } description: {
                            Text(emptyStateMessage)
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(workspaceViewModel.sections) { section in
                                PositionSectionView(section: section)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PositionFilterSidebar(
                selectedPositionFilter: $selectedPositionFilter,
                selectedProtocol: $selectedProtocol,
                positionFilterTotals: positionFilterTotals,
                protocolOptions: availableProtocolOptions
            )
        }
        .navigationTitle(Self.navigationTitle)
        .onChange(of: selectedPositionFilter) { _, _ in
            reconcileSelectedProtocol(availableProtocols: availableProtocolOptions)
        }
        .onChange(of: availableProtocolOptions) { _, newOptions in
            reconcileSelectedProtocol(availableProtocols: newOptions)
        }
    }

    private var emptyStateTitle: String {
        activePositions.isEmpty ? "No Positions" : "No Matching Positions"
    }

    private var emptyStateMessage: String {
        if activePositions.isEmpty {
            return "Add a position to start building the workspace."
        }

        if selectedProtocol == nil {
            return "Adjust the sidebar filters to narrow the position workspace."
        }

        return "Clear the protocol filter or choose a protocol that still exists for the selected position type."
    }

    private func reconcileSelectedProtocol(availableProtocols: [String]) {
        guard let selectedProtocol else {
            return
        }

        guard availableProtocols.contains(selectedProtocol) else {
            self.selectedProtocol = nil
            return
        }
    }

    private func protocolDisplayName(for position: Position) -> String {
        let protocolID = trimmedNonEmpty(position.protocolId)
        let protocolName = trimmedNonEmpty(position.protocolName)
        let accountName = trimmedNonEmpty(position.account?.name)

        if protocolID != nil, let protocolName {
            return protocolName
        }

        if let protocolID {
            return protocolID
        }

        if let protocolName {
            return protocolName
        }

        if let accountName {
            return accountName
        }

        return "Unknown Protocol"
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
