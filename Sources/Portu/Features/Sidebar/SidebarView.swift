import ComposableArchitecture
import PortuCore
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selectedSection) {
                ForEach(SidebarLayout.navigationSections) { section in
                    SidebarNavigationSection(section: section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Portu")

            SidebarFooter(
                items: SidebarLayout.footerItems,
                isSettingsSelected: store.isSettingsPresented) {
                    store.send(.settingsSelected)
                }
        }
    }

    private var selectedSection: Binding<SidebarSection?> {
        Binding(
            get: { store.sidebarSelection },
            set: { if let section = $0 { store.send(.sectionSelected(section)) } })
    }
}

private struct SidebarNavigationSection: View {
    let section: SidebarLayoutSection

    var body: some View {
        Section {
            ForEach(section.items) { item in
                SidebarNavigationRow(item: item)
            }
        } header: {
            if let title = section.title {
                Text(title)
            }
        }
        .disabled(section.isDisabled)
    }
}

private struct SidebarNavigationRow: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case let .section(section):
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        case .strategies:
            Label("Strategies", systemImage: "lightbulb")
                .foregroundStyle(.tertiary)
        case .settings:
            EmptyView()
        }
    }
}

private struct SidebarFooter: View {
    let items: [SidebarItem]
    let isSettingsSelected: Bool
    let settingsAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ForEach(items) { item in
                switch item {
                case .settings:
                    Button {
                        settingsAction()
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .foregroundStyle(isSettingsSelected ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSettingsSelected ? Color.accentColor.opacity(0.16) : .clear))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                case .section, .strategies:
                    EmptyView()
                }
            }
        }
        .background(.bar)
    }
}
