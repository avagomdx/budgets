import Foundation
import SwiftData
import SwiftUI

// MARK: - Categories and expenses

@Model
final class BudgetCategory {
    var name: String = ""
    var icon: String = "tag"
    var colorName: String = "blue"
    /// Budget per pay period. 0 = no budget.
    var budget: Double = 0
    /// Move unspent (or overspent) budget to the next period.
    var carryOver: Bool = false
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Expense.category)
    var expenses: [Expense]? = []

    @Relationship(deleteRule: .nullify, inverse: \FixedCostTemplate.category)
    var fixedCostTemplates: [FixedCostTemplate]? = []

    @Relationship(deleteRule: .nullify, inverse: \PeriodFixedCost.category)
    var periodFixedCosts: [PeriodFixedCost]? = []

    init(name: String, icon: String, colorName: String, budget: Double, carryOver: Bool = false, sortOrder: Int) {
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.budget = budget
        self.carryOver = carryOver
        self.sortOrder = sortOrder
    }

    var color: Color { CategoryPalette.color(named: colorName) }
}

@Model
final class Expense {
    var amount: Double = 0
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now
    var category: BudgetCategory?
    /// Bank transaction ID for imported expenses (used to skip duplicates). Empty for manual ones.
    var externalID: String = ""
    /// "bank" for imported expenses, empty for manual ones.
    var source: String = ""

    init(amount: Double, date: Date, note: String, category: BudgetCategory?) {
        self.amount = amount
        self.date = date
        self.note = note
        self.category = category
        self.createdAt = .now
    }
}

// MARK: - Defaults (templates used for every new period)

@Model
final class IncomeSource {
    var key: String = UUID().uuidString
    var name: String = ""
    var amount: Double = 0
    var sortOrder: Int = 0

    init(name: String, amount: Double, sortOrder: Int) {
        self.key = UUID().uuidString
        self.name = name
        self.amount = amount
        self.sortOrder = sortOrder
    }
}

@Model
final class FixedCostTemplate {
    var key: String = UUID().uuidString
    var name: String = ""
    /// Amount per occurrence (per week, month, quarter or year).
    var amount: Double = 0
    var frequencyRaw: String = CostFrequency.monthly.rawValue
    var modeRaw: String = ChargeMode.whenDue.rawValue
    /// A date on which this cost is (or was) charged. Used for weekly, quarterly and yearly costs.
    var anchorDate: Date = Date.now
    var isSavings: Bool = false
    var sortOrder: Int = 0
    var category: BudgetCategory?

    init(name: String, amount: Double, frequency: CostFrequency, mode: ChargeMode,
         anchorDate: Date, isSavings: Bool, sortOrder: Int) {
        self.key = UUID().uuidString
        self.name = name
        self.amount = amount
        self.frequencyRaw = frequency.rawValue
        self.modeRaw = mode.rawValue
        self.anchorDate = anchorDate
        self.isSavings = isSavings
        self.sortOrder = sortOrder
    }

    var frequency: CostFrequency {
        get { CostFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var mode: ChargeMode {
        get { ChargeMode(rawValue: modeRaw) ?? .whenDue }
        set { modeRaw = newValue.rawValue }
    }

    var spec: FixedCostSpec {
        FixedCostSpec(amount: amount, frequency: frequency, mode: mode, anchorDate: anchorDate)
    }
}

// MARK: - Pay periods

@Model
final class BudgetPeriod {
    /// First day of the period (start of day).
    var startDate: Date = Date.now
    /// Start of the next period (exclusive end).
    var endDate: Date = Date.now
    /// The new-period check-in has been completed.
    var isCheckedIn: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \IncomeEntry.period)
    var incomes: [IncomeEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \PeriodFixedCost.period)
    var fixedCosts: [PeriodFixedCost]? = []

    init(startDate: Date, endDate: Date, isCheckedIn: Bool) {
        self.startDate = startDate
        self.endDate = endDate
        self.isCheckedIn = isCheckedIn
    }

    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }

    var isCurrent: Bool { contains(.now) }

    /// Last day that belongs to this period.
    var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
    }

    var sortedIncomes: [IncomeEntry] {
        (incomes ?? []).sorted { lhs, rhs in
            if lhs.isExtra != rhs.isExtra { return !lhs.isExtra }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.date < rhs.date
        }
    }

    var sortedFixedCosts: [PeriodFixedCost] {
        (fixedCosts ?? []).sorted { lhs, rhs in
            if lhs.isSavings != rhs.isSavings { return !lhs.isSavings }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var totalIncome: Double { (incomes ?? []).reduce(0) { $0 + $1.amount } }
    var totalFixedCosts: Double { (fixedCosts ?? []).reduce(0) { $0 + $1.amount } }
    var totalSavings: Double { (fixedCosts ?? []).filter(\.isSavings).reduce(0) { $0 + $1.amount } }
}

@Model
final class IncomeEntry {
    var name: String = ""
    var amount: Double = 0
    /// Extra income during the period (refund, Tikkie, ...), as opposed to regular income.
    var isExtra: Bool = false
    var date: Date = Date.now
    var sortOrder: Int = 0
    /// Key of the IncomeSource this was copied from, if any.
    var sourceKey: String = ""
    var period: BudgetPeriod?

    init(name: String, amount: Double, isExtra: Bool, date: Date, sortOrder: Int, sourceKey: String) {
        self.name = name
        self.amount = amount
        self.isExtra = isExtra
        self.date = date
        self.sortOrder = sortOrder
        self.sourceKey = sourceKey
    }
}

@Model
final class PeriodFixedCost {
    var name: String = ""
    /// Amount for this period.
    var amount: Double = 0
    var isSavings: Bool = false
    var sortOrder: Int = 0
    /// Key of the FixedCostTemplate this was copied from, if any.
    var templateKey: String = ""
    /// Short explanation, e.g. "4 × € 10 weekly" or "Yearly, spread".
    var detail: String = ""
    var period: BudgetPeriod?
    var category: BudgetCategory?

    init(name: String, amount: Double, isSavings: Bool, sortOrder: Int, templateKey: String, detail: String) {
        self.name = name
        self.amount = amount
        self.isSavings = isSavings
        self.sortOrder = sortOrder
        self.templateKey = templateKey
        self.detail = detail
    }
}

// MARK: - Bank connections (Enable Banking)

@Model
final class BankConnection {
    var sessionID: String = ""
    var bankName: String = ""
    var bankCountry: String = ""
    var validUntil: Date = Date.now
    var createdAt: Date = Date.now
    var lastSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \BankAccountLink.connection)
    var accounts: [BankAccountLink]? = []

    init(sessionID: String, bankName: String, bankCountry: String, validUntil: Date) {
        self.sessionID = sessionID
        self.bankName = bankName
        self.bankCountry = bankCountry
        self.validUntil = validUntil
        self.createdAt = .now
    }

    var isValid: Bool { validUntil > .now }
}

@Model
final class BankAccountLink {
    var uid: String = ""
    var iban: String = ""
    var name: String = ""
    var currency: String = ""
    var isEnabled: Bool = true
    var connection: BankConnection?

    init(uid: String, iban: String, name: String, currency: String) {
        self.uid = uid
        self.iban = iban
        self.name = name
        self.currency = currency
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if !iban.isEmpty { return iban }
        return "Account"
    }
}

// MARK: - Colors and icons

struct PaletteColor: Identifiable {
    let name: String
    let color: Color
    var id: String { name }
}

enum CategoryPalette {
    static let colors: [PaletteColor] = [
        PaletteColor(name: "green", color: .green),
        PaletteColor(name: "mint", color: .mint),
        PaletteColor(name: "teal", color: .teal),
        PaletteColor(name: "blue", color: .blue),
        PaletteColor(name: "indigo", color: .indigo),
        PaletteColor(name: "purple", color: .purple),
        PaletteColor(name: "pink", color: .pink),
        PaletteColor(name: "red", color: .red),
        PaletteColor(name: "orange", color: .orange),
        PaletteColor(name: "yellow", color: .yellow),
        PaletteColor(name: "brown", color: .brown),
        PaletteColor(name: "gray", color: .gray),
    ]

    static let icons: [String] = [
        "cart", "fork.knife", "cup.and.saucer", "car", "fuelpump", "tram",
        "house", "bolt", "phone", "tshirt", "bag", "gift",
        "gamecontroller", "film", "book", "airplane", "figure.run", "heart",
        "cross.case", "pawprint", "graduationcap", "wrench.and.screwdriver", "creditcard", "ellipsis.circle",
        "shield", "repeat", "banknote", "building.columns", "drop", "tv",
    ]

    static func color(named name: String) -> Color {
        colors.first { $0.name == name }?.color ?? .gray
    }
}

// MARK: - Suggestions for the setup wizard

struct CategorySuggestion {
    let name: String
    let icon: String
    let color: String
    let budget: Double
}

enum Suggestions {
    static let categories: [CategorySuggestion] = [
        CategorySuggestion(name: "Groceries", icon: "cart", color: "green", budget: 400),
        CategorySuggestion(name: "Dining out", icon: "fork.knife", color: "orange", budget: 150),
        CategorySuggestion(name: "Transport", icon: "car", color: "blue", budget: 150),
        CategorySuggestion(name: "Leisure", icon: "gamecontroller", color: "purple", budget: 100),
        CategorySuggestion(name: "Clothing", icon: "tshirt", color: "pink", budget: 75),
        CategorySuggestion(name: "Other", icon: "ellipsis.circle", color: "gray", budget: 100),
    ]

    static let incomeNames: [String] = [
        "Salary", "Partner's salary", "Healthcare allowance", "Rent allowance",
        "Child benefit", "Side income",
    ]

    static let fixedCostNames: [String] = [
        "Rent / mortgage", "Energy", "Water", "Health insurance", "Internet & TV",
        "Phone", "Insurance", "Municipal taxes", "Car insurance", "Road tax",
        "Streaming", "Gym", "Savings",
    ]
}
