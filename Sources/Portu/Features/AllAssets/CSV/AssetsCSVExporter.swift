import Foundation

struct AssetsCSVExporter {
    func makeCSV(rows: [AssetTableRow]) -> String {
        let header = "Symbol,Name,Category,Net Amount,Price,Value"
        let lines = rows.map(makeLine(for:))

        return ([header] + lines).joined(separator: "\n")
    }

    private func makeLine(
        for row: AssetTableRow
    ) -> String {
        [
            escaped(row.symbol),
            escaped(row.name),
            escaped(row.category.rawValue.capitalized),
            escaped(decimalString(for: row.netAmount)),
            escaped(decimalString(for: row.price)),
            escaped(decimalString(for: row.value))
        ]
        .joined(separator: ",")
    }

    private func decimalString(
        for value: Decimal
    ) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func escaped(
        _ field: String
    ) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }

        let escapedQuotes = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedQuotes)\""
    }
}
