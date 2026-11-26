import Foundation

enum AppFormat {
    static let locale = Locale(identifier: "nl_NL")
    static let currencyCode = "EUR"
}

extension Double {
    /// Bijv. "€ 12,50"
    var euro: String {
        formatted(.currency(code: AppFormat.currencyCode).locale(AppFormat.locale))
    }

    /// Bijv. "12,50" — voor in een tekstveld.
    var editableAmount: String {
        formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(AppFormat.locale))
    }
}

extension String {
    /// Leest "12,50", "12.5" of "€ 12" als bedrag. Geeft nil bij ongeldige invoer of 0.
    var parsedAmount: Double? {
        let cleaned = self
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
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

    /// Bijv. "November 2026"
    var monthTitle: String {
        formatted(.dateTime.month(.wide).year().locale(AppFormat.locale)).capitalizedFirst
    }

    /// "Vandaag", "Gisteren" of bijv. "Maandag 23 november"
    var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Vandaag" }
        if calendar.isDateInYesterday(self) { return "Gisteren" }
        return formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppFormat.locale)).capitalizedFirst
    }

    /// Bijv. "23 nov"
    var shortDay: String {
        formatted(.dateTime.day().month(.abbreviated).locale(AppFormat.locale))
    }
}
