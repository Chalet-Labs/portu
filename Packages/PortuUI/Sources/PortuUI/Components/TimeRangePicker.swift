import SwiftUI

public struct TimeRangePicker: View {
    public enum Range: String, CaseIterable, Identifiable, Sendable {
        case oneWeek = "1w"
        case oneMonth = "1m"
        case threeMonths = "3m"
        case oneYear = "1y"
        case yearToDate = "YTD"

        public var id: String { rawValue }
        public var label: String { rawValue }
    }

    @Binding private var selection: Range

    public init(selection: Binding<Range>) {
        _selection = selection
    }

    public var body: some View {
        Picker("Time Range", selection: $selection) {
            ForEach(Range.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }
}
