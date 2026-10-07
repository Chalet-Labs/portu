import PortuUI
import SwiftUI

/// The page title with the reload status beside it. The status shares the title's row instead
/// of getting a row of its own, and is centered on it rather than baseline-aligned, so a
/// reload changes what the status shows and never how tall the page is.
struct PerformancePageHeader: View {
    let isLoading: Bool
    let error: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DashboardPageHeader("Performance")
            status
                .frame(maxWidth: 360, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var status: some View {
        if isLoading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading performance data\u{2026}")
            }
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
        } else if let error {
            Label(
                "Performance data unavailable: \(error)",
                systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardWarning)
                .lineLimit(1)
                .help(error)
        }
    }
}
