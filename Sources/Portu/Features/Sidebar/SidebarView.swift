import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Overview", systemImage: "chart.pie")
                    .tag(SidebarSection.overview)

                Label("Exposure", systemImage: "square.grid.3x3.middle.filled")
                    .tag(SidebarSection.exposure)

                Label("Performance", systemImage: "chart.xyaxis.line")
                    .tag(SidebarSection.performance)
            }

            Section("Portfolio") {
                Label("All Assets", systemImage: "bitcoinsign.circle")
                    .tag(SidebarSection.allAssets)

                Label("All Positions", systemImage: "tray.full")
                    .tag(SidebarSection.allPositions)
            }

            Section("Management") {
                Label("Accounts", systemImage: "building.columns")
                    .tag(SidebarSection.accounts)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Portu")
        .toolbar {
            ToolbarItem {
                Button("Add Account", systemImage: "plus") {
                    // TODO: Add account flow
                }
            }
        }
    }
}
