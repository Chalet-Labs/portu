import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The historical provider publishes the USD half of the valuation inputs. These pin the wiring:
/// which stored rows reach it, and that the selected currency and its rate never touch it. The
/// close and fraction rules are Core's.
@MainActor
struct HistoricalMarketPricesProviderTests {
    /// 2025-10-06 12:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_759_752_000)
    private static var retainedWindows: [NSWindow] = []

    private static func day(_ offset: Int) -> Date {
        HistoricalPriceCalendar.utcStartOfDay(for: now).addingTimeInterval(TimeInterval(offset) * 86400)
    }

    private static func point(
        _ priceID: String,
        _ price: Decimal,
        day offset: Int,
        currency: FiatCurrency = .usd) -> HistoricalPricePoint {
        HistoricalPricePoint(coinGeckoId: priceID, day: day(offset), currency: currency, price: price)
    }

    /// A same-day CHF row priced above the USD one: a leaked CHF row would win the close.
    private static var mixedCurrencyPoints: [HistoricalPricePoint] {
        [
            point("bitcoin", 50000, day: 0),
            point("bitcoin", 70000, day: 0, currency: .chf),
            point("ethereum", 1000, day: -1),
            point("ethereum", 2000, day: -1, currency: .chf),
            point("ethereum", 1100, day: 0),
            point("chf-only", 10, day: 0, currency: .chf),
            point("old", 5, day: -3)
        ]
    }

    private static func expectUSDOnly(_ prices: HistoricalMarketPrices) throws {
        #expect(prices.closesUSD["bitcoin"] == HistoricalClose(day: day(0), price: 50000))
        #expect(prices.closesUSD["ethereum"] == HistoricalClose(day: day(0), price: 1100))
        #expect(prices.closesUSD["chf-only"] == nil)
        #expect(prices.closesUSD["old"] == nil)
        let tenPercent = try #require(Decimal(string: "0.1"))
        #expect(prices.changes24h == ["ethereum": tenPercent])
    }

    @Test func `entry point publishes usd closes with their day and drops non usd rows`() throws {
        let prices = HistoricalMarketPricesFeature.prices(
            from: Self.mixedCurrencyPoints,
            isBackfillEnabled: true,
            now: Self.now)

        try Self.expectUSDOnly(prices)
    }

    @Test func `entry point publishes the consecutive day usd fraction`() {
        let prices = HistoricalMarketPricesFeature.prices(
            from: [
                Self.point("ethereum", 1000, day: -1),
                Self.point("ethereum", 2000, day: -1, currency: .chf),
                Self.point("ethereum", 1100, day: 0),
                Self.point("bitcoin", 50000, day: -2),
                Self.point("bitcoin", 60000, day: 0)
            ],
            isBackfillEnabled: true,
            now: Self.now)

        #expect(prices.changes24h["ethereum"] == Decimal(string: "0.1"))
        #expect(prices.changes24h["bitcoin"] == nil)
    }

    @Test func `entry point is empty when historical backfill is disabled`() {
        let prices = HistoricalMarketPricesFeature.prices(
            from: Self.mixedCurrencyPoints,
            isBackfillEnabled: false,
            now: Self.now)

        #expect(prices == .empty)
    }

    @Test func `rows stored without a currency count as usd`() {
        let legacy = Self.point("ethereum", 1100, day: 0)
        legacy.currency = nil

        let prices = HistoricalMarketPricesFeature.prices(from: [legacy], isBackfillEnabled: true, now: Self.now)

        #expect(prices.closesUSD["ethereum"]?.price == 1100)
    }

    @Test func `provider publishes usd closes unconverted while chf is selected`() throws {
        let host = try HostedProvider()
        defer { host.tearDown() }

        try #require(waitUntil { host.recorder.prices.closesUSD["bitcoin"] != nil }, "the provider never published the closes")

        try Self.expectUSDOnly(host.recorder.prices)
    }

    @Test func `provider publishes nothing once historical backfill is turned off`() throws {
        let host = try HostedProvider()
        defer { host.tearDown() }
        try #require(waitUntil { host.recorder.prices.closesUSD["bitcoin"] != nil }, "the provider never published the closes")

        host.defaults.set(false, forKey: HistoricalPriceBackfillSettings.isEnabledKey)

        #expect(waitUntil { host.recorder.prices == .empty }, "the provider kept publishing with backfill off")
    }

    /// Hosts the real provider over the mixed-currency rows, with CHF selected at 0.88 and backfill
    /// on in a throwaway defaults suite, so the app's own defaults are never read or written.
    @MainActor
    private final class HostedProvider {
        let recorder = Recorder()
        let defaults: UserDefaults
        private let suiteName = "HistoricalMarketPricesProviderTests.\(UUID().uuidString)"
        private let window: NSWindow

        init() throws {
            self.defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.set(true, forKey: HistoricalPriceBackfillSettings.isEnabledKey)

            let container = try ModelContainerFactory().makeInMemory()
            for point in HistoricalMarketPricesProviderTests.mixedCurrencyPoints {
                container.mainContext.insert(point)
            }
            try container.mainContext.save()

            let appState = AppState()
            appState.selectedCurrency = .chf
            appState.currentUSDToDisplayRate = try #require(Decimal(string: "0.88"))

            let hostingView = NSHostingView(rootView: HistoricalPricesProvider(
                now: HistoricalMarketPricesProviderTests.now) { [recorder] in
                    Sink(recorder: recorder)
                }
                .modelContainer(container)
                .environment(appState)
                .defaultAppStorage(defaults))
            hostingView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
            self.window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hostingView
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            HistoricalMarketPricesProviderTests.retainedWindows.append(window)
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// Spins the main run loop, which is what lets SwiftUI evaluate the hosted view.
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }
}

@MainActor
private final class Recorder {
    var prices: HistoricalMarketPrices = .empty
}

private struct Sink: View {
    @Environment(\.historicalMarketPrices) private var prices
    let recorder: Recorder

    var body: some View {
        recorder.prices = prices
        return Text("\(prices.closesUSD.count)")
    }
}
