import Foundation
import SwiftData

/// Creates pay periods and computes period totals.
@MainActor
enum PeriodManager {
    static let leftoverSourceKey = "leftover-from-previous-period"

    // MARK: - Creating periods

    /// Makes sure a period exists for today. Missed periods are created as well;
    /// only the newest one still needs a check-in.
    static func ensureCurrentPeriod(context: ModelContext, rule: PaydayRule = .saved) {
        let now = Date.now
        let descriptor = FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)])
        let periods = (try? context.fetch(descriptor)) ?? []

        guard var latest = periods.last else {
            let start = rule.periodStart(containing: now)
            _ = createPeriod(start: start, end: rule.nextPayday(after: start), checkedIn: false, context: context)
            try? context.save()
            return
        }

        var created = 0
        while latest.endDate <= now && created < 36 {
            let start = latest.endDate
            let end = rule.nextPayday(after: start)
            latest = createPeriod(start: start, end: end, checkedIn: end <= now, context: context)
            created += 1
        }
        if created > 0 {
            try? context.save()
        }
    }

    /// Creates a period and fills it with copies of the default income and fixed costs.
    @discardableResult
    static func createPeriod(start: Date, end: Date, checkedIn: Bool, context: ModelContext) -> BudgetPeriod {
        let period = BudgetPeriod(startDate: start, endDate: end, isCheckedIn: checkedIn)
        context.insert(period)

        let sources = (try? context.fetch(FetchDescriptor<IncomeSource>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        for (index, source) in sources.enumerated() {
            let entry = IncomeEntry(name: source.name, amount: source.amount, isExtra: false,
                                    date: start, sortOrder: index, sourceKey: source.key)
            context.insert(entry)
            entry.period = period
        }

        let templates = (try? context.fetch(FetchDescriptor<FixedCostTemplate>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        var order = 0
        for template in templates {
            let charge = template.spec.charge(start: start, end: end)
            guard charge.amount > 0 else { continue }
            let cost = PeriodFixedCost(name: template.name, amount: charge.amount, isSavings: template.isSavings,
                                       sortOrder: order, templateKey: template.key, detail: charge.detail)
            context.insert(cost)
            cost.period = period
            cost.category = template.category
            order += 1
        }
        return period
    }

    /// Adds default fixed costs that aren't in the period yet (matched by their default).
    /// Costs already in the period are left as they are. Returns how many were added.
    @discardableResult
    static func addMissingDefaultFixedCosts(to period: BudgetPeriod, context: ModelContext) -> Int {
        let existingKeys = Set((period.fixedCosts ?? []).map(\.templateKey).filter { !$0.isEmpty })
        let templates = (try? context.fetch(FetchDescriptor<FixedCostTemplate>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        var order = ((period.fixedCosts ?? []).map(\.sortOrder).max() ?? -1) + 1
        var added = 0
        for template in templates where !existingKeys.contains(template.key) {
            let charge = template.spec.charge(start: period.startDate, end: period.endDate)
            guard charge.amount > 0 else { continue }
            let cost = PeriodFixedCost(name: template.name, amount: charge.amount, isSavings: template.isSavings,
                                       sortOrder: order, templateKey: template.key, detail: charge.detail)
            context.insert(cost)
            cost.period = period
            cost.category = template.category
            order += 1
            added += 1
        }
        try? context.save()
        return added
    }

    /// Salary came early: end the current period today and start the next one.
    static func startNextPeriodEarly(current: BudgetPeriod, context: ModelContext, rule: PaydayRule = .saved) {
        let today = Calendar.current.startOfDay(for: .now)
        guard today > current.startDate else { return }
        let scheduledPayday = current.endDate
        current.endDate = today
        let end = rule.nextPayday(after: max(scheduledPayday, today))
        createPeriod(start: today, end: end, checkedIn: false, context: context)
        try? context.save()
    }

    /// After the payday rule changes: move the end of the current period to the new next payday.
    static func applyRuleToCurrentPeriod(context: ModelContext, rule: PaydayRule) {
        let descriptor = FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)])
        guard let latest = ((try? context.fetch(descriptor)) ?? []).last else { return }
        latest.endDate = rule.nextPayday(after: latest.startDate)
        try? context.save()
        ensureCurrentPeriod(context: context, rule: rule)
    }

    /// Deletes all budget data so the setup wizard can run again. Bank connections are kept.
    static func resetAllData(context: ModelContext) {
        for item in (try? context.fetch(FetchDescriptor<Expense>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<IncomeEntry>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<PeriodFixedCost>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<BudgetPeriod>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<IncomeSource>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<FixedCostTemplate>())) ?? [] { context.delete(item) }
        try? context.save()
    }

    // MARK: - Looking up periods

    /// The selected period, or the current one, or the newest one.
    static func resolve(_ id: PersistentIdentifier?, in periods: [BudgetPeriod]) -> BudgetPeriod? {
        if let id, let match = periods.first(where: { $0.persistentModelID == id }) {
            return match
        }
        return periods.last(where: { $0.isCurrent }) ?? periods.last
    }

    static func previous(of period: BudgetPeriod, in periods: [BudgetPeriod]) -> BudgetPeriod? {
        periods.last { $0.startDate < period.startDate }
    }

    // MARK: - Totals

    static func expenses(in period: BudgetPeriod, from expenses: [Expense]) -> [Expense] {
        expenses.filter { period.contains($0.date) }
    }

    static func spent(in period: BudgetPeriod, expenses: [Expense]) -> Double {
        expenses.reduce(0) { total, expense in
            period.contains(expense.date) ? total + expense.amount : total
        }
    }

    static func spent(in period: BudgetPeriod, category: BudgetCategory, expenses: [Expense]) -> Double {
        let id = category.persistentModelID
        return expenses.reduce(0) { total, expense in
            guard period.contains(expense.date), expense.category?.persistentModelID == id else { return total }
            return total + expense.amount
        }
    }

    /// Income − fixed costs − spent.
    static func leftToSpend(in period: BudgetPeriod, expenses: [Expense]) -> Double {
        period.totalIncome - period.totalFixedCosts - spent(in: period, expenses: expenses)
    }

    /// Unspent (or overspent, negative) budget carried into `period` for a category with carry-over on.
    static func carriedIn(category: BudgetCategory, period: BudgetPeriod,
                          periods: [BudgetPeriod], expenses: [Expense]) -> Double {
        guard category.carryOver, category.budget > 0 else { return 0 }
        var carry = 0.0
        for earlier in periods where earlier.startDate < period.startDate {
            let spentThere = spent(in: earlier, category: category, expenses: expenses)
            carry = category.budget + carry - spentThere
        }
        return carry
    }

    /// Budget available for a category in a period, including carry-over.
    static func effectiveBudget(category: BudgetCategory, period: BudgetPeriod,
                                periods: [BudgetPeriod], expenses: [Expense]) -> Double {
        category.budget + carriedIn(category: category, period: period, periods: periods, expenses: expenses)
    }

    /// Fixed costs (incl. savings) in a period assigned to a category.
    static func fixedCosts(in period: BudgetPeriod, category: BudgetCategory) -> Double {
        let id = category.persistentModelID
        return (period.fixedCosts ?? []).reduce(0) { total, cost in
            cost.category?.persistentModelID == id ? total + cost.amount : total
        }
    }

    /// Gives every period copy of a default fixed cost the same category as the default.
    static func syncCategory(of template: FixedCostTemplate, context: ModelContext) {
        let key = template.key
        let descriptor = FetchDescriptor<PeriodFixedCost>(predicate: #Predicate<PeriodFixedCost> { $0.templateKey == key })
        for cost in (try? context.fetch(descriptor)) ?? [] {
            cost.category = template.category
        }
        try? context.save()
    }

    /// Number of days left in the period, including today.
    static func daysLeft(in period: BudgetPeriod) -> Int {
        let today = Calendar.current.startOfDay(for: .now)
        let days = Calendar.current.dateComponents([.day], from: today, to: period.endDate).day ?? 0
        return max(days, 1)
    }
}
