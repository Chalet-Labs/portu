import SwiftUI

struct AddAccountSheet: View {
    static let tabTitles = ["Chain Account", "Manual Account", "Exchange Account"]
    static let bulkImportTitle = "Bulk Import"
    static let bulkImportHelp = "Coming soon"

    private let secretsCoordinator: AccountSecretsCoordinator
    private let onComplete: @MainActor () -> Void

    init(
        secretsCoordinator: AccountSecretsCoordinator = AccountSecretsCoordinator(),
        onComplete: @escaping @MainActor () -> Void = {}
    ) {
        self.secretsCoordinator = secretsCoordinator
        self.onComplete = onComplete
    }

    var body: some View {
        TabView {
            ChainAccountForm(onComplete: onComplete)
                .tabItem {
                    Label(Self.tabTitles[0], systemImage: "link")
                }

            ManualAccountForm(onComplete: onComplete)
                .tabItem {
                    Label(Self.tabTitles[1], systemImage: "square.and.pencil")
                }

            ExchangeAccountForm(
                secretsCoordinator: secretsCoordinator,
                onComplete: onComplete
            )
            .tabItem {
                Label(Self.tabTitles[2], systemImage: "building.columns")
            }
        }
        .frame(minWidth: 460, minHeight: 340)
    }
}
