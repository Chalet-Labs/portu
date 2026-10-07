import AppKit
import Foundation
@testable import Portu
import SwiftUI
import Testing

@MainActor
struct PerformancePageHeaderTests {
    private func height(isLoading: Bool = false, error: String? = nil) -> CGFloat {
        let header = PerformancePageHeader(isLoading: isLoading, error: error)
            .frame(width: 900)
        let hostingView = NSHostingView(rootView: header)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    @Test func `loading and failed states keep the idle header height`() {
        let idle = height()

        #expect(idle > 0, "A zero height means nothing was laid out, so the comparisons below prove nothing")
        #expect(height(isLoading: true) == idle, "The loading indicator must not add a row")
        #expect(height(error: "Store unavailable") == idle, "The error notice must not add a row")
        #expect(
            height(error: String(repeating: "Store unavailable. ", count: 40)) == idle,
            "A long error must stay on one line")
    }
}
