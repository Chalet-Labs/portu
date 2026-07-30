import Foundation
@testable import Portu
import PortuCore
import Testing

struct ProviderPortfolioHistoryTests {
    private let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func `provider history stops strictly before earliest fresh local day`() {
        let day1 = Date(timeIntervalSince1970: 1_704_067_200)
        let day2 = day1.addingTimeInterval(86400)
        let day3 = day2.addingTimeInterval(86400)
        let provider = [
            providerPoint(day1, 90),
            providerPoint(day2, 100),
            providerPoint(day3, 110)
        ]
        let local = [
            LocalPortfolioValueObservation(
                timestamp: day2.addingTimeInterval(3600),
                usdValue: 105,
                isFresh: true),
            LocalPortfolioValueObservation(
                timestamp: day3,
                usdValue: 115,
                isFresh: false)
        ]

        let merged = ProviderPortfolioHistory.merge(
            provider: provider,
            local: local,
            selectedAccountID: accountID)

        #expect(merged.map(\.source) == [.zerion, .local, .local])
        #expect(merged.map(\.usdValue) == [90, 105, 115])
    }

    @Test func `provider is sole authority until a fresh local snapshot exists`() {
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let merged = ProviderPortfolioHistory.merge(
            provider: [providerPoint(day, 90)],
            local: [.init(timestamp: day, usdValue: 50, isFresh: false)],
            selectedAccountID: accountID)

        #expect(merged.map(\.source) == [.zerion])
        #expect(merged.map(\.usdValue) == [90])
    }

    @Test func `provider never fills gaps after local authority begins`() {
        let day1 = Date(timeIntervalSince1970: 1_704_067_200)
        let day2 = day1.addingTimeInterval(86400)
        let day3 = day2.addingTimeInterval(86400)
        let merged = ProviderPortfolioHistory.merge(
            provider: [providerPoint(day2, 100)],
            local: [
                .init(timestamp: day1, usdValue: 90, isFresh: true),
                .init(timestamp: day3, usdValue: 110, isFresh: true)
            ],
            selectedAccountID: accountID)

        #expect(merged.map(\.timestamp) == [day1, day3])
        #expect(merged.allSatisfy { $0.source == .local })
    }

    @Test func `range filtering preserves an earlier local authority boundary`() {
        let authorityDay = Date(timeIntervalSince1970: 1_704_067_200)
        let rangeStart = authorityDay.addingTimeInterval(86400)
        let providerDay = rangeStart.addingTimeInterval(86400)

        let merged = ProviderPortfolioHistory.merge(
            provider: [providerPoint(providerDay, 100)],
            local: [
                .init(timestamp: authorityDay, usdValue: 90, isFresh: true),
                .init(timestamp: providerDay, usdValue: 0, isFresh: false)
            ],
            selectedAccountID: accountID,
            startDate: rangeStart)

        #expect(merged.map(\.timestamp) == [providerDay])
        #expect(merged.map(\.source) == [.local])
        #expect(merged.map(\.isReliable) == [false])
    }

    @Test func `provider history never enters all accounts scope`() {
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let merged = ProviderPortfolioHistory.merge(
            provider: [providerPoint(day, 90)],
            local: [.init(timestamp: day, usdValue: 100, isFresh: true)],
            selectedAccountID: nil)

        #expect(merged.map(\.source) == [.local])
    }

    @Test func `estimates remain outside retained provider coverage`() {
        let day1 = Date(timeIntervalSince1970: 1_704_067_200)
        let day2 = day1.addingTimeInterval(86400)
        let day3 = day2.addingTimeInterval(86400)
        let day4 = day3.addingTimeInterval(86400)
        let estimates = [day1, day2, day3, day4].map {
            HistoricalPortfolioValuePoint(date: $0, value: 100, kind: .estimated)
        }

        let retained = ProviderPortfolioHistory.estimatesOutsideProviderCoverage(
            estimates,
            providerDates: [
                day2.addingTimeInterval(3600),
                day3.addingTimeInterval(3600)
            ])

        #expect(retained.map(\.date) == [day1, day4])
    }

    @Test func `missing FX yields longest contiguous converted suffix without spot fallback`() {
        let day1 = Date(timeIntervalSince1970: 1_704_067_200)
        let day2 = day1.addingTimeInterval(86400)
        let day3 = day2.addingTimeInterval(86400)
        let result = ProviderPortfolioHistory.convertProviderHistory(
            [providerPoint(day1, 100), providerPoint(day2, 110), providerPoint(day3, 120)],
            currency: .chf,
            historicalRatesByDay: [day2: 0.9, day3: 0.8])

        #expect(result.points.map(\.value) == [99, 96])
        #expect(result.historicalFXUnavailableBefore == day2)
    }

    private func providerPoint(_ date: Date, _ value: Decimal) -> ProviderPortfolioValueDTO {
        ProviderPortfolioValueDTO(
            timestamp: date,
            usdValue: value,
            provider: .zerion,
            coverage: .providerReported)
    }
}
