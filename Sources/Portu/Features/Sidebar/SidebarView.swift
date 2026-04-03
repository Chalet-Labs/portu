import ComposableArchitecture
import PortuCore
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        List(selection: Binding(
            get: { store.selectedSection },
            set: { if let section = $0 { store.send(.sectionSelected(section)) } })) {
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

                Section {
                    Label("Strategies", systemImage: "lightbulb")
                        .foregroundStyle(.tertiary)
                } header: {
                    Text("")
                }
                .disabled(true)
            }
            .listStyle(.sidebar)
            .navigationTitle("Portu")
    }
}
