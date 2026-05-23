import Foundation

enum OverviewPriceDisplay {
    static let assetLabelMaxLength = 6
    private static let priceLocale = Locale(identifier: "en_US_POSIX")
    private static let compactCurrencyThreshold = 1_000_000.0

    static func assetLabel(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(assetLabelMaxLength))
    }

    static func price(_ price: Decimal) -> String {
        "$ \(formattedNumber(price))"
    }

    static func compactPrice(_ price: Decimal) -> String {
        let number = abs(NSDecimalNumber(decimal: price).doubleValue)
        if number > 0, number < 0.00000001 {
            return "$ <1e-8"
        }
        return self.price(price)
    }

    static func currency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let sign = number < 0 ? "-$ " : "$ "
        return sign + formattedMagnitude(abs(number), compactFractionDigits: 1)
    }

    static func axisCurrency(_ value: Double) -> String {
        let sign = value < 0 ? "-$ " : "$ "
        return sign + standardNumber(abs(value), maximumFractionDigits: 0)
    }

    static func amount(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let sign = number < 0 ? "-" : ""
        return sign + formattedMagnitude(abs(number), compactFractionDigits: 2)
    }

    private static func formattedNumber(_ price: Decimal) -> String {
        let number = NSDecimalNumber(decimal: price).doubleValue
        let absoluteValue = abs(number)
        let maximumFractionDigits = maximumFractionDigits(for: absoluteValue)
        let formatted = standardNumber(absoluteValue, maximumFractionDigits: maximumFractionDigits)
        if absoluteValue > 0, formatted == "0" {
            let minimumDisplayedValue = pow(10, -Double(maximumFractionDigits))
            return "<\(standardNumber(minimumDisplayedValue, maximumFractionDigits: maximumFractionDigits))"
        }
        return formatted
    }

    private static func formattedMagnitude(
        _ absoluteValue: Double,
        compactFractionDigits: Int) -> String {
        if absoluteValue >= 1_000_000_000_000 {
            return compactNumber(absoluteValue / 1_000_000_000_000, suffix: "T", maximumFractionDigits: compactFractionDigits)
        }
        if absoluteValue >= 1_000_000_000 {
            return compactNumber(absoluteValue / 1_000_000_000, suffix: "B", maximumFractionDigits: compactFractionDigits)
        }
        if absoluteValue >= compactCurrencyThreshold {
            return compactNumber(absoluteValue / compactCurrencyThreshold, suffix: "M", maximumFractionDigits: compactFractionDigits)
        }
        return standardNumber(absoluteValue, maximumFractionDigits: absoluteValue >= 100 ? 0 : 2)
    }

    private static func compactNumber(
        _ value: Double,
        suffix: String,
        maximumFractionDigits: Int) -> String {
        value.formatted(.number
            .locale(priceLocale)
            .grouping(.automatic)
            .precision(.fractionLength(0 ... maximumFractionDigits))) + suffix
    }

    private static func standardNumber(
        _ value: Double,
        maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = priceLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func maximumFractionDigits(for absoluteValue: Double) -> Int {
        if absoluteValue >= 1000 { return 0 }
        if absoluteValue >= 1 { return 4 }
        if absoluteValue >= 0.0001 { return 6 }
        return 8
    }
}
