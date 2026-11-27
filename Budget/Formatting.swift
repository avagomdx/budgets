import Foundation

enum AppFormat {
    /// Follows the device's language and region settings.
    static var locale: Locale { .autoupdatingCurrent }

    /// Currency of the device's region, falling back to euro.
    static var currencyCode: String { Locale.current.currency?.identifier ?? "EUR" }

    /// Short symbol for the currency, e.g. "€" or "$".
    static var currencySymbol: String {
        let symbol = Double(0).asCurrency
            .filter { !$0.isNumber && $0 != "." && $0 != "," && !$0.isWhitespace }
        return symbol.isEmpty ? currencyCode : symbol
    }

    /// e.g. "20 Nov – 19 Dec", with the year added when it isn't the current year.
    static func periodTitle(start: Date, lastDay: Date) -> String {
        let calendar = Calendar.current
        let from = start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        var to = lastDay.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        if calendar.component(.year, from: lastDay) != calendar.component(.year, from: .now) {
            to += " \(calendar.component(.year, from: lastDay))"
        }
        return "\(from) – \(to)"
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

    /// Text field value: empty for 0.
    var editableAmountOrEmpty: String {
        self == 0 ? "" : editableAmount
    }
}

extension String {
    /// Reads "12,50", "12.5", "€ 12", "1.500" or "1.234,56" as an amount.
    /// A separator followed by exactly three digits is treated as a thousands separator.
    /// Returns nil for empty or invalid input.
    var amountValue: Double? {
        let kept = filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !kept.isEmpty else { return nil }

        var normalized = kept
        if let lastSeparator = kept.lastIndex(where: { $0 == "," || $0 == "." }) {
            let fraction = String(kept[kept.index(after: lastSeparator)...])
            let wholePart = String(kept[..<lastSeparator].filter { $0.isNumber })
            if fraction.isEmpty {
                normalized = wholePart
            } else if fraction.count == 3 {
                normalized = wholePart + fraction
            } else {
                normalized = wholePart + "." + fraction
            }
        }
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// Amount greater than zero, or nil.
    var parsedAmount: Double? {
        guard let value = amountValue, value > 0 else { return nil }
        return value
    }

    /// Empty means 0; invalid input gives nil.
    var parsedNonNegativeAmount: Double? {
        if trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return amountValue
    }

    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

extension Date {
    /// "Today", "Yesterday" or e.g. "Monday, November 23"
    var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppFormat.locale)).capitalizedFirst
    }

    /// e.g. "Fri 19 Dec"
    var shortDayTitle: String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppFormat.locale))
    }
}
