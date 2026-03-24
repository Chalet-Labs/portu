import SwiftUI
import PortuCore
import PortuUI

struct PerformanceControls: View {
    let supportedModes: [PerformanceChartMode]
    @Binding var selectedMode: PerformanceChartMode
    @Binding var selectedRange: PerformanceRange
    @Binding var selectedAccountID: UUID?
    @Binding var enabledCategories: Set<AssetCategory>

    let accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(supportedModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                Spacer()

                Picker("Account", selection: $selectedAccountID) {
                    Text("All Accounts").tag(Optional<UUID>.none)

                    ForEach(accounts, id: \.id) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .frame(maxWidth: 240)
            }

            TimeRangePicker(selection: selectedPickerRange)
                .frame(maxWidth: 320)

            if selectedMode == .assets {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(AssetCategory.allCases, id: \.self) { category in
                            let isEnabled = enabledCategories.contains(category)
                            let title = categoryTitle(for: category)

                            Button {
                                toggleCategory(category)
                            } label: {
                                HStack(spacing: 6) {
                                    if let symbolName = Self.chipSymbolName(isEnabled: isEnabled) {
                                        Image(systemName: symbolName)
                                            .imageScale(.small)
                                    }

                                    Text(title)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                isEnabled ? Color.white : .primary
                            )
                            .background(
                                isEnabled
                                ? Color.accentColor
                                : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isEnabled ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2),
                                        lineWidth: isEnabled ? 1.5 : 1
                                    )
                            )
                            .accessibilityLabel(title)
                            .accessibilityValue(Self.chipAccessibilityValue(isEnabled: isEnabled))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectedPickerRange: Binding<TimeRangePicker.Range> {
        Binding(
            get: {
                selectedRange.pickerRange
            },
            set: { newValue in
                selectedRange = PerformanceRange(pickerRange: newValue)
            }
        )
    }

    private func toggleCategory(
        _ category: AssetCategory
    ) {
        enabledCategories = Self.toggledCategories(enabledCategories, toggling: category)
    }

    static func toggledCategories(
        _ enabledCategories: Set<AssetCategory>,
        toggling category: AssetCategory
    ) -> Set<AssetCategory> {
        var updatedCategories = enabledCategories

        if updatedCategories.contains(category) {
            if updatedCategories.count > 1 {
                updatedCategories.remove(category)
            }
        } else {
            updatedCategories.insert(category)
        }

        return updatedCategories
    }

    static func chipSymbolName(
        isEnabled: Bool
    ) -> String? {
        isEnabled ? "checkmark" : nil
    }

    static func chipAccessibilityValue(
        isEnabled: Bool
    ) -> String {
        isEnabled ? "Selected" : "Not selected"
    }

    private func categoryTitle(
        for category: AssetCategory
    ) -> String {
        switch category {
        case .major:
            "Major"
        case .stablecoin:
            "Stablecoin"
        case .defi:
            "DeFi"
        case .meme:
            "Meme"
        case .privacy:
            "Privacy"
        case .fiat:
            "Fiat"
        case .governance:
            "Governance"
        case .other:
            "Other"
        }
    }
}
