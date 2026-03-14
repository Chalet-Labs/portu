import SwiftUI

/// Displays a Decimal value formatted as currency.
public struct CurrencyText: View {
    let value: Decimal
    let currencyCode: String

    public init(_ value: Decimal, currencyCode: String = "USD") {
        self.value = value
        self.currencyCode = currencyCode
    }

    public var body: some View {
        Text(value, format: .currency(code: currencyCode))
    }
}
