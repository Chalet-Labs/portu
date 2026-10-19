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

/// Owns the dashboard's one position query and publishes the active portfolio to the content,
/// so the sidebar header, the Overview top bar and All Positions share one walk of the store
/// per store change instead of each re-fetching and re-faulting it (#103: only values cross).
/// It reads nothing else, so a price tick or a navigation click does not re-run it.
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
