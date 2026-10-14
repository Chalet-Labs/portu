import PortuCore
import PortuUI
import SwiftUI

struct PositionFilterSidebar: View {
    let typeOptions: [AllPositionsTypeOption]
    let protocolOptions: [AllPositionsProtocolOption]
    let currencyCode: String
    @Binding var selectedType: PositionType?
    @Binding var selectedProtocol: ProtocolFilter

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
                    ForEach(typeOptions) { option in
                        Button {
                            selectedType = option.type
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(selectedType == option.type ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                                Spacer()
                                Text(AllPositionsFormat.currency(option.total, code: currencyCode))
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

                    ForEach(protocolOptions) { option in
                        Button {
                            selectedProtocol = option.filter
                        } label: {
                            HStack {
                                Text(option.name)
                                    .foregroundStyle(selectedProtocol == option.filter ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                                Spacer()
                                Text(AllPositionsFormat.currency(option.total, code: currencyCode))
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
