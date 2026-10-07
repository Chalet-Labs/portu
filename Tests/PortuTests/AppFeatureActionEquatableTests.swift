import ComposableArchitecture
import Foundation
@testable import Portu
import Testing

/// `AppFeature.Action` equality must follow its payloads. The hand-written `==` this
/// replaces compared every failure as equal and had no case for the historical FX top-up.
struct AppFeatureActionEquatableTests {
    private static func failureActions(_ message: String) -> [AppFeature.Action] {
        [
            .syncCompleted(.failure(SyncFailure(message: message))),
            .accountSyncCompleted(.failure(SyncFailure(message: message))),
            .scheduledSyncCompleted(.failure(SyncFailure(message: message))),
            .priceFetchFailed(PriceFetchFailure(message: message))
        ]
    }

    @Test func `failure actions with different messages compare unequal`() {
        let first = Self.failureActions("Network unavailable")
        let second = Self.failureActions("Rate limited")

        for (lhs, rhs) in zip(first, second) {
            #expect(lhs != rhs)
        }
    }

    @Test func `failure actions with the same message compare equal`() {
        let first = Self.failureActions("Network unavailable")
        let second = Self.failureActions("Network unavailable")

        for (lhs, rhs) in zip(first, second) {
            #expect(lhs == rhs)
        }
    }

    @Test func `different failure actions never compare equal`() {
        let actions = Self.failureActions("Network unavailable")

        for (offset, lhs) in actions.enumerated() {
            for rhs in actions[(offset + 1)...] {
                #expect(lhs != rhs)
            }
        }
    }

    @Test func `sync failures compare by the engine error they wrap`() {
        let allFailed = SyncFailure(SyncError.allAccountsFailed)
        let notFound = SyncFailure(SyncError.accountNotFound)

        #expect(allFailed == SyncFailure(SyncError.allAccountsFailed))
        #expect(allFailed != notFound)
        #expect(allFailed.syncError == .allAccountsFailed)
        #expect(allFailed.message == SyncError.allAccountsFailed.localizedDescription)
    }

    @Test func `historical fx top up completions compare by payload`() {
        let result = HistoricalFXRefreshResult(
            currency: .eur,
            insertedHistoricalRates: 3,
            updatedHistoricalRates: 2)
        let otherResult = HistoricalFXRefreshResult(
            currency: .eur,
            insertedHistoricalRates: 4,
            updatedHistoricalRates: 2)

        #expect(
            AppFeature.Action.historicalFXTopUpCompleted(.eur, .success(result))
                == .historicalFXTopUpCompleted(.eur, .success(result)))
        #expect(
            AppFeature.Action.historicalFXTopUpCompleted(.eur, .success(result))
                != .historicalFXTopUpCompleted(.eur, .success(otherResult)))
        #expect(
            AppFeature.Action.historicalFXTopUpCompleted(.eur, .success(result))
                != .historicalFXTopUpCompleted(.chf, .success(result)))
        #expect(
            AppFeature.Action.historicalFXTopUpCompleted(.eur, .failure(CurrencyConversionRefreshError(message: "offline")))
                == .historicalFXTopUpCompleted(.eur, .failure(CurrencyConversionRefreshError(message: "offline"))))
        #expect(
            AppFeature.Action.historicalFXTopUpCompleted(.eur, .failure(CurrencyConversionRefreshError(message: "offline")))
                != .historicalFXTopUpCompleted(.eur, .failure(CurrencyConversionRefreshError(message: "timeout"))))
    }
}
