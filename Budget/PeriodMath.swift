import Foundation

// Pure date/amount logic (Foundation only, no SwiftUI/SwiftData).

enum CostFrequency: String, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    /// Per-occurrence label used next to the amount field.
    var perLabel: String {
        switch self {
        case .weekly: return "per week"
        case .monthly: return "per month"
        case .quarterly: return "per quarter"
        case .yearly: return "per year"
        }
    }
}

enum ChargeMode: String, CaseIterable, Identifiable {
    /// Only counted in periods in which it's charged.
    case whenDue
    /// Spread evenly over every period as a reserve.
    case spread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whenDue: return "Only when due"
        case .spread: return "Spread evenly"
        }
    }
}

enum WeekendShift: String, CaseIterable, Identifiable {
    case sameDay
    case previousFriday
    case nextMonday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameDay: return "Same day"
        case .previousFriday: return "Friday before"
        case .nextMonday: return "Monday after"
        }
    }
}

/// When salary arrives, and therefore when a pay period starts.
struct PaydayRule: Equatable {
    var day: Int
    var saturday: WeekendShift
    var sunday: WeekendShift

    static let dayKey = "paydayDay"
    static let saturdayKey = "paydaySaturdayShift"
    static let sundayKey = "paydaySundayShift"

    static let standard = PaydayRule(day: 20, saturday: .previousFriday, sunday: .nextMonday)

    /// The rule saved in UserDefaults (falls back to the standard rule).
    static var saved: PaydayRule {
        let defaults = UserDefaults.standard
        let day = defaults.object(forKey: dayKey) as? Int ?? standard.day
        let saturday = WeekendShift(rawValue: defaults.string(forKey: saturdayKey) ?? "") ?? standard.saturday
        let sunday = WeekendShift(rawValue: defaults.string(forKey: sundayKey) ?? "") ?? standard.sunday
        return PaydayRule(day: day, saturday: saturday, sunday: sunday)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(day, forKey: Self.dayKey)
        defaults.set(saturday.rawValue, forKey: Self.saturdayKey)
        defaults.set(sunday.rawValue, forKey: Self.sundayKey)
    }

    /// Payday in the given month, after applying the weekend rule (start of day).
    func payday(year: Int, month: Int, calendar: Calendar = .current) -> Date {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 28
        let clampedDay = min(max(day, 1), daysInMonth)
        var date = calendar.date(from: DateComponents(year: year, month: month, day: clampedDay)) ?? firstOfMonth

        // Gregorian weekday: 1 = Sunday, 7 = Saturday.
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 7 {
            switch saturday {
            case .sameDay: break
            case .previousFriday: date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            case .nextMonday: date = calendar.date(byAdding: .day, value: 2, to: date) ?? date
            }
        } else if weekday == 1 {
            switch sunday {
            case .sameDay: break
            case .previousFriday: date = calendar.date(byAdding: .day, value: -2, to: date) ?? date
            case .nextMonday: date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
        }
        return calendar.startOfDay(for: date)
    }

    /// Paydays around the month of `date` (a few months back and forward).
    private func paydays(around date: Date, offsets: [Int], calendar: Calendar) -> [Date] {
        let components = calendar.dateComponents([.year, .month], from: date)
        let firstOfMonth = calendar.date(from: components) ?? date
        return offsets.compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: firstOfMonth) else { return nil }
            let c = calendar.dateComponents([.year, .month], from: month)
            return payday(year: c.year ?? 2000, month: c.month ?? 1, calendar: calendar)
        }
    }

    /// Start of the pay period that contains `date`: the latest payday on or before it.
    func periodStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let candidates = paydays(around: date, offsets: [-2, -1, 0, 1], calendar: calendar)
        return candidates.filter { $0 <= date }.max() ?? calendar.startOfDay(for: date)
    }

    /// The first payday strictly after `date`.
    func nextPayday(after date: Date, calendar: Calendar = .current) -> Date {
        let candidates = paydays(around: date, offsets: [-1, 0, 1, 2], calendar: calendar)
        return candidates.filter { $0 > date }.min()
            ?? calendar.date(byAdding: .month, value: 1, to: date)
            ?? date
    }
}

/// A fixed cost definition, independent of storage.
struct FixedCostSpec {
    var amount: Double
    var frequency: CostFrequency
    var mode: ChargeMode
    var anchorDate: Date

    /// Amount charged in the period [start, end), plus a short explanation.
    func charge(start: Date, end: Date, calendar: Calendar = .current) -> (amount: Double, detail: String) {
        switch frequency {
        case .monthly:
            return (amount, "Monthly")

        case .weekly:
            if mode == .spread {
                return (Self.round(amount * 52 / 12), "Weekly, averaged per month")
            }
            let count = weeklyOccurrences(start: start, end: end, calendar: calendar)
            return (Self.round(amount * Double(count)), "\(count) × \(amount.asCurrency) weekly")

        case .quarterly:
            if mode == .spread {
                return (Self.round(amount / 3), "Quarterly, spread")
            }
            let count = monthlyOccurrences(every: 3, start: start, end: end, calendar: calendar)
            return (Self.round(amount * Double(count)), "Quarterly, due this period")

        case .yearly:
            if mode == .spread {
                return (Self.round(amount / 12), "Yearly, spread")
            }
            let count = monthlyOccurrences(every: 12, start: start, end: end, calendar: calendar)
            return (Self.round(amount * Double(count)), "Yearly, due this period")
        }
    }

    /// Rough per-period amount, used for estimates in the setup wizard.
    var averagePerPeriod: Double {
        switch frequency {
        case .weekly: return Self.round(amount * 52 / 12)
        case .monthly: return amount
        case .quarterly: return Self.round(amount / 3)
        case .yearly: return Self.round(amount / 12)
        }
    }

    func weeklyOccurrences(start: Date, end: Date, calendar: Calendar) -> Int {
        let anchor = calendar.startOfDay(for: anchorDate)
        let daysBetween = calendar.dateComponents([.day], from: anchor, to: start).day ?? 0
        let firstWeek = Int((Double(daysBetween) / 7).rounded(.down)) - 1
        var count = 0
        for week in firstWeek...(firstWeek + 10) {
            if let date = calendar.date(byAdding: .day, value: week * 7, to: anchor), date >= start, date < end {
                count += 1
            }
        }
        return count
    }

    func monthlyOccurrences(every months: Int, start: Date, end: Date, calendar: Calendar) -> Int {
        let anchor = calendar.startOfDay(for: anchorDate)
        let monthsBetween = calendar.dateComponents([.month], from: anchor, to: start).month ?? 0
        let first = Int((Double(monthsBetween) / Double(months)).rounded(.down)) - 1
        var count = 0
        for step in first...(first + 3) {
            if let date = calendar.date(byAdding: .month, value: step * months, to: anchor), date >= start, date < end {
                count += 1
            }
        }
        return count
    }

    static func round(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
