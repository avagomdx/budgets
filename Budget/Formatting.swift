import Foundation

enum AppFormat {
    /// Follows the device's language and region settings.
    static var locale: Locale { .autoupdatingCurrent }

    /// Currency of the device's region, falling back to euro.
    static var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    /// Short symbol for the currency, e.g. "€" or "$".
    static var currencySymbol: String {
        let symbol = 0.0.formatted(.currency(code: currencyCode).locale(locale))
            .filter { !$0.isNumber && $0 != "." && $0 != "," && !$0.isWhitespace }
        return symbol.isEmpty ? currencyCode : symbol
    }
}

extension Double {
    /// Formatted as currency, e.g. "€12.50"
    var asCurrency: String {
        formatted(.currency(code: AppFormat.currencyCode).locale(AppFormat.locale))
    }

    /// Plain number for a text field, e.g. "12.50"
    var editableAmount: String {
        formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(AppFormat.locale))
    }
}

extension String {
    /// Parses "12,50", "12.5" or "€ 12" as an amount. Returns nil for invalid input or 0.
    var parsedAmount: Double? {
        let cleaned = self
            .filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

extension Date {
    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }

    func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    /// e.g. "November 2026"
    var monthTitle: String {
        formatted(.dateTime.month(.wide).year().locale(AppFormat.locale)).capitalizedFirst
    }

    /// "Today", "Yesterday" or e.g. "Monday, November 23"
    var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppFormat.locale)).capitalizedFirst
    }
}
