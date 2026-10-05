import Foundation
@testable import Portu
import Testing

/// Every view shares one formatter cache through `OverviewPriceDisplay`, so a price must format
/// the same however many threads render at once, including when the cache is still cold.
struct OverviewDecimalFormatterCacheTests {
    private struct Tier {
        let value: Double
        let maximumFractionDigits: Int
        let expected: String
    }

    private struct DisplayCase: Sendable {
        let expected: String
        let render: @Sendable () -> String
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    /// One entry per fraction-digit tier the display code asks for.
    private static let tiers = [
        Tier(value: 2866.478, maximumFractionDigits: 0, expected: "2,866"),
        Tier(value: 42.126, maximumFractionDigits: 2, expected: "42.13"),
        Tier(value: 12.3456789, maximumFractionDigits: 4, expected: "12.3457"),
        Tier(value: 5, maximumFractionDigits: 4, expected: "5"),
        Tier(value: 0.000123456, maximumFractionDigits: 6, expected: "0.000123"),
        Tier(value: 0.000000123456, maximumFractionDigits: 8, expected: "0.00000012")
    ]

    @Test func `each fraction digit tier formats with its own precision`() {
        let cache = OverviewDecimalFormatterCache(locale: Self.locale)

        for tier in Self.tiers {
            let formatted = cache.string(from: tier.value, maximumFractionDigits: tier.maximumFractionDigits)
            #expect(formatted == tier.expected)
        }
    }

    @Test func `tiers keep their precision when requested interleaved`() {
        let cache = OverviewDecimalFormatterCache(locale: Self.locale)

        for round in 0 ..< 3 {
            for tier in Self.tiers.reversed() {
                let formatted = cache.string(from: tier.value, maximumFractionDigits: tier.maximumFractionDigits)
                #expect(formatted == tier.expected, "round \(round), \(tier.maximumFractionDigits) digits")
            }
        }
    }

    /// A race detector rather than a proof: an unsynchronised insert into the formatter table only
    /// misbehaves when first uses of different tiers collide, so every trial starts from a cold cache.
    @Test(.timeLimit(.minutes(1)))
    func `concurrent first use of every tier formats correctly`() async {
        let failures = await DeadlockWatchdog.guarding("formatter cache contention") {
            Self.hammerColdCaches(trials: 300, workers: 16)
        }

        #expect(failures == [])
    }

    @Test(.timeLimit(.minutes(1)))
    func `display helpers format identically from many threads`() async throws {
        let cases = try Self.displayCases()

        let failures = await DeadlockWatchdog.guarding("display helper contention") {
            Self.hammerDisplayHelpers(cases, workers: 8, rounds: 200)
        }

        #expect(failures == [])
    }

    // MARK: - Helpers

    private static func hammerColdCaches(trials: Int, workers: Int) -> [String] {
        let failures = ConcurrentFailureLog()

        for trial in 0 ..< trials {
            let cache = OverviewDecimalFormatterCache(locale: locale)
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                // Start each worker on a different tier so they race to create different formatters.
                for offset in tiers.indices {
                    let tier = tiers[(worker + offset) % tiers.count]
                    let formatted = cache.string(from: tier.value, maximumFractionDigits: tier.maximumFractionDigits)
                    failures.check(
                        formatted == tier.expected,
                        "trial \(trial) worker \(worker): \(tier.maximumFractionDigits) digits gave \(formatted)")
                }
            }
        }
        return failures.all
    }

    private static func hammerDisplayHelpers(_ cases: [DisplayCase], workers: Int, rounds: Int) -> [String] {
        let failures = ConcurrentFailureLog()

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for round in 0 ..< rounds {
                for offset in cases.indices {
                    let displayCase = cases[(worker + offset) % cases.count]
                    let rendered = displayCase.render()
                    failures.check(
                        rendered == displayCase.expected,
                        "worker \(worker) round \(round): expected \(displayCase.expected), got \(rendered)")
                }
            }
        }
        return failures.all
    }

    private static func displayCases() throws -> [DisplayCase] {
        func decimal(_ text: String) throws -> Decimal {
            try #require(Decimal(string: text, locale: locale))
        }

        let large = try decimal("2866.478")
        let medium = try decimal("12.3456789")
        let small = try decimal("0.000123456")
        let tiny = try decimal("0.00000012")
        let belowDisplayable = try decimal("0.0000000001")
        let wholeDollars = try decimal("8889")
        let cents = try decimal("42.126")
        let tokenAmount = try decimal("123.456")

        return [
            DisplayCase(expected: "$ 2,866") { OverviewPriceDisplay.price(large) },
            DisplayCase(expected: "$ 12.3457") { OverviewPriceDisplay.price(medium) },
            DisplayCase(expected: "$ 0.000123") { OverviewPriceDisplay.price(small) },
            DisplayCase(expected: "$ 0.00000012") { OverviewPriceDisplay.price(tiny) },
            DisplayCase(expected: "$ <0.00000001") { OverviewPriceDisplay.price(belowDisplayable) },
            DisplayCase(expected: "$ 8,889") { OverviewPriceDisplay.currency(wholeDollars) },
            DisplayCase(expected: "$ 42.13") { OverviewPriceDisplay.currency(cents) },
            DisplayCase(expected: "123") { OverviewPriceDisplay.amount(tokenAmount) },
            DisplayCase(expected: "$ 20,000") { OverviewPriceDisplay.axisCurrency(20000) }
        ]
    }
}
