import ComposableArchitecture
import PortuCore
import SwiftUI

struct GeneralSettingsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        SettingsPage(tab: .general) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Display Currency",
                    subtitle: "Choose the fiat currency used to display asset prices and portfolio totals across Portu.",
                    icon: .priceUpdates) {
                        SettingsCurrencyPicker(store: store)
                    }

                SettingsInfoCard(
                    title: "Auto-saved",
                    message: "Preferences are stored locally with AppStorage and apply across Portu views.")
            }
        }
    }
}

struct SettingsCurrencyPicker: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Display currency")
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .semibold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text("Portfolio values display in the selected fiat currency.")
                    .font(.caption)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Picker("Display currency", selection: currencyBinding) {
                ForEach(FiatCurrency.allCases, id: \.self) { currency in
                    Text(currency.displayCode).tag(currency)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.vertical, 4)
    }

    private var currencyBinding: Binding<FiatCurrency> {
        Binding(
            // A non-USD switch defers `selectedCurrency` until its FX rate arrives, so the
            // picker must show the effective target during that window, not the old currency.
            get: { store.pendingCurrency ?? store.selectedCurrency },
            set: { store.send(.displayCurrencySelected($0)) })
    }
}
