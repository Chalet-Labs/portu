import ComposableArchitecture
import Foundation
import SwiftData

// swiftformat:disable redundantSendable

/// The value chart's store boundary (#124). As with `PortfolioProjectorClient`, the closure is not
/// `@MainActor`: the build fetches on the chart projector's own executor, and the reducer awaits it
/// from a `.run` effect.
struct PortfolioValueChartProjectorClient {
    var build: @Sendable (PortfolioProjectionRequest) async throws -> PortfolioValueChartSource
}

extension PortfolioValueChartProjectorClient: DependencyKey {
    /// `PortuApp` replaces this with `.live(modelContainer:)` at Store creation. A missed override
    /// throws, so the dashboard keeps its no-chart state instead of trapping.
    static let liveValue = Self(build: { _ in
        throw PortfolioProjectorError(message: "PortfolioValueChartProjectorClient.liveValue must be overridden at Store creation")
    })

    static let testValue = Self(build: { _ in .empty })
}

extension DependencyValues {
    var portfolioValueChartProjector: PortfolioValueChartProjectorClient {
        get { self[PortfolioValueChartProjectorClient.self] }
        set { self[PortfolioValueChartProjectorClient.self] = newValue }
    }
}

extension PortfolioValueChartProjectorClient {
    /// Not the holdings projector's queue: `@ModelActor` binds its executor to the queue it is
    /// created on, so sharing one would hold a holdings build behind a chart build.
    private static let projectorCreationQueue = DispatchQueue(
        label: "com.portu.portfolio-value-chart-projector",
        qos: .utility)

    /// Created on its own queue for the reason `PortfolioProjectorClient.makeProjector` gives.
    static func makeProjector(modelContainer: ModelContainer) async -> PortfolioValueChartProjector {
        await withCheckedContinuation { continuation in
            projectorCreationQueue.async {
                continuation.resume(returning: PortfolioValueChartProjector(modelContainer: modelContainer))
            }
        }
    }

    static func live(modelContainer: ModelContainer) -> Self {
        let projectorTask = Task {
            await makeProjector(modelContainer: modelContainer)
        }
        return Self(build: { request in
            let projector = await projectorTask.value
            return try await projector.build(request)
        })
    }
}
