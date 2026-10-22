import Foundation
import os
import Synchronization

/// The read model's two hot intervals (#123): one projector build and one revaluation. Each is an
/// `OSSignposter` interval, read with Instruments on a Release build, and its most recent duration
/// is kept for the Debug server's `/state/portfolio/timings`.
enum PortfolioTimings {
    struct Snapshot: Equatable, Sendable {
        var projectionBuild: Duration?
        var valuation: Duration?
    }

    struct Interval {
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
    }

    private static let signposter = OSSignposter(subsystem: "com.portu.app", category: "PortfolioReadModel")
    private static let latest = Mutex(Snapshot())

    static var snapshot: Snapshot {
        latest.withLock { $0 }
    }

    static func beginProjectionBuild() -> Interval {
        Interval(state: signposter.beginInterval("PortfolioProjectionBuild"), start: .now)
    }

    static func endProjectionBuild(_ interval: Interval) {
        signposter.endInterval("PortfolioProjectionBuild", interval.state)
        let elapsed = ContinuousClock.now - interval.start
        latest.withLock { $0.projectionBuild = elapsed }
    }

    /// Runs one revaluation inside the `PortfolioValuation` interval.
    static func measureValuation<Value>(_ body: () -> Value) -> Value {
        let state = signposter.beginInterval("PortfolioValuation")
        let start = ContinuousClock.now
        let value = body()
        signposter.endInterval("PortfolioValuation", state)
        let elapsed = ContinuousClock.now - start
        latest.withLock { $0.valuation = elapsed }
        return value
    }
}
