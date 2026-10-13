/// The first cell of a table's hidden-balances line (F3), shared by Exposure and All Assets.
enum HiddenBalancesLabel {
    /// "small" when every hidden row is dust, else "hidden".
    static func title(rowCount: Int, isAllDust: Bool) -> String {
        "\(rowCount) \(isAllDust ? "small" : "hidden") \(rowCount == 1 ? "balance" : "balances")"
    }
}
