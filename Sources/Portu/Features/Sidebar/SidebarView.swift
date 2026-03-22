import SwiftUI
import SwiftData
import PortuCore

struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        List(selection: $selection) {
            Section("PORTU") {
                Label("Overview", systemImage: "chart.pie")
                    .tag(SidebarSection.overview)
                Label("Exposure", systemImage: "chart.bar.xaxis")
                    .tag(SidebarSection.exposure)
                Label("Performance", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(SidebarSection.performance)
            }

            Section("PORTFOLIO") {
                Label("All Assets", systemImage: "bitcoinsign.circle")
                    .tag(SidebarSection.allAssets)
                Label("All Positions", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSection.allPositions)
            }

            Section("MANAGEMENT") {
                Label("Accounts", systemImage: "person.2")
                    .tag(SidebarSection.accounts)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Portu")
    }
}
