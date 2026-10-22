import PortuCore
import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// The active accounts' positions as values, built once per store change by
    /// `ActivePortfolioProvider`. Empty outside one.
    @Entry var activePortfolio = ActivePortfolioProjection(inputs: [], cards: [])

    /// How the provider builds the projection. Production never sets it; tests swap it to count
    /// or replace builds.
    @Entry var activePortfolioBuilder: ActivePortfolioBuilder = .live
}

struct ActivePortfolioBuilder {
    let build: @MainActor ([Position]) -> ActivePortfolioProjection

    static var live: ActivePortfolioBuilder {
        ActivePortfolioBuilder { ActivePortfolioProjection($0) }
    }
}

/// Owns All Positions' one position query and publishes the active portfolio to it, walking the
/// store once per store change (#103: only values cross). It reads nothing else, so a price tick does
/// not re-run it. It is mounted only around All Positions, its last reader, because the walk runs on
/// the main actor; #124 moves that page to the portfolio read model and deletes this provider.
struct ActivePortfolioProvider<Content: View>: View {
    @Environment(\.activePortfolioBuilder) private var builder
    @Query private var positions: [Position]

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.environment(\.activePortfolio, builder.build(positions))
    }
}
