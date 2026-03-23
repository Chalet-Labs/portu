import SwiftUI
import PortuCore
import PortuUI

struct PerformanceControls: View {
    let supportedModes: [PerformanceChartMode]
    @Binding var selectedMode: PerformanceChartMode
    @Binding var selectedRange: PerformanceRange
    @Binding var selectedAccountID: UUID?

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
}
