import ComposableArchitecture
import SwiftUI

struct SettingsUpdateChannelPicker: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Release channel")
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .semibold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text("Choose between stable releases and preview alpha builds.")
                    .font(.caption)
                    .foregroundStyle(SettingsDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Picker("Release channel", selection: channelBinding) {
                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                    Text(channel.title).tag(channel)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.vertical, 4)
    }

    private var channelBinding: Binding<UpdateChannel> {
        Binding(
            get: { store.updatePreferences.channel },
            set: { store.send(.setUpdateChannel($0)) })
    }
}

extension UpdateChannel {
    var title: String {
        switch self {
        case .stable: "Stable"
        case .alpha: "Alpha"
        }
    }
}
