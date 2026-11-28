import Foundation
import SwiftData
import UserNotifications

// MARK: - Automatic bank sync

@MainActor
enum BankSync {
    static let autoSyncKey = "bankAutoSync"
    private static let lastSyncKey = "bankLastAutoSync"
    private static let dismissedKey = "bankDismissedTransactionIDs"
    private static let lastMonitorKey = "fixedCostMonitorLastRun"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: autoSyncKey) as? Bool ?? true
    }

    static var lastSync: Date? {
        let value = UserDefaults.standard.double(forKey: lastSyncKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Remembers a transaction you removed from the review list, so it isn't added again.
    static func dismiss(externalID: String) {
        guard !externalID.isEmpty else { return }
        var ids = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        ids.append(externalID)
        UserDefaults.standard.set(Array(ids.suffix(3000)), forKey: dismissedKey)
    }

    /// Fetches new bank transactions and adds them as expenses to check.
    /// Runs at most once an hour unless `force` is set. Returns how many were added.
    @discardableResult
    static func syncIfNeeded(context: ModelContext, force: Bool = false) async -> Int {
        guard force || isEnabled else { return 0 }
        let connections = ((try? context.fetch(FetchDescriptor<BankConnection>())) ?? []).filter(\.isValid)
        guard !connections.isEmpty, !BankSettings.appID.isEmpty, BankSettings.hasPrivateKey else { return 0 }
        if !force, let last = lastSync, Date.now.timeIntervalSince(last) < 3600 { return 0 }

        let periods = (try? context.fetch(FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let periodStart = periods.last(where: { $0.isCurrent })?.startDate
            ?? Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        var from = periodStart
        if let last = lastSync, let overlap = Calendar.current.date(byAdding: .day, value: -3, to: last), overlap < from {
            from = overlap
        }

        do {
            let fetched = try await BankLink.fetchTransactions(context: context, from: from)
            let added = addForReview(fetched.transactions, ownIBANs: fetched.ownIBANs, context: context)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastSyncKey)
            Notifications.checkBudgets(context: context)
            await runWeeklyMonitorIfDue(context: context)
            return added
        } catch {
            return 0
        }
    }

    private static func addForReview(_ transactions: [FetchedTransaction], ownIBANs: Set<String>,
                                     context: ModelContext) -> Int {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let known = Set(expenses.map(\.externalID).filter { !$0.isEmpty })
            .union(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
        let templates = (try? context.fetch(FetchDescriptor<FixedCostTemplate>())) ?? []
        let fixedKeys = Set(templates.map { MerchantKey.make($0.name) })
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let rules = (try? context.fetch(FetchDescriptor<CategoryRule>())) ?? []

        var remembered: [String: BudgetCategory] = [:]
        for expense in expenses.sorted(by: { $0.date < $1.date }) where expense.source == "bank" && !expense.needsReview {
            if let category = expense.category {
                remembered[MerchantKey.make(expense.note)] = category
            }
        }

        var added = 0
        for transaction in transactions where transaction.isDebit {
            guard !known.contains(transaction.id),
                  !ownIBANs.contains(transaction.counterpartyIBAN),
                  !fixedKeys.contains(transaction.merchantKey) else { continue }
            let expense = Expense(amount: transaction.amount, date: transaction.date,
                                  note: transaction.counterparty, category: nil)
            expense.externalID = transaction.id
            expense.source = "bank"
            expense.needsReview = true
            context.insert(expense)
            expense.category = remembered[transaction.merchantKey]
                ?? AutoCategory.suggest(for: transaction.counterparty + " " + transaction.details,
                                        in: categories, rules: rules)
            added += 1
        }
        try? context.save()
        return added
    }

    /// Once a week: look for fixed costs that changed price and new recurring payments.
    private static func runWeeklyMonitorIfDue(context: ModelContext) async {
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: lastMonitorKey)
        guard Date.now.timeIntervalSince1970 - last > 7 * 86_400 else { return }
        defaults.set(Date.now.timeIntervalSince1970, forKey: lastMonitorKey)
        guard Notifications.isEnabled(.fixedCostChanges),
              let result = try? await FixedCostMonitor.check(context: context) else { return }
        let count = result.changes.count + result.newPayments.count
        guard count > 0 else { return }
        Notifications.send(id: "fixed-cost-monitor",
                           title: "Your fixed costs changed",
                           body: count == 1
                               ? "1 fixed cost changed or is new. Open Budget to check it."
                               : "\(count) fixed costs changed or are new. Open Budget to check them.")
    }
}

// MARK: - Fixed cost monitor

struct FixedCostChange: Identifiable {
    let id: String
    let template: FixedCostTemplate
    let newAmount: Double
}

@MainActor
enum FixedCostMonitor {
    /// Compares recurring payments from the bank with your default fixed costs.
    static func check(context: ModelContext) async throws
        -> (changes: [FixedCostChange], newPayments: [RecurringSuggestion]) {
        let from = Calendar.current.date(byAdding: .day, value: -185, to: .now) ?? .now
        let fetched = try await BankLink.fetchTransactions(context: context, from: from)
        let suggestions = RecurringDetector.detect(fetched.transactions, ownIBANs: fetched.ownIBANs)
        let templates = (try? context.fetch(FetchDescriptor<FixedCostTemplate>())) ?? []

        var changes: [FixedCostChange] = []
        var matchedSuggestions: Set<String> = []
        for template in templates {
            let key = MerchantKey.make(template.name)
            let candidates = suggestions.filter {
                $0.merchantKey == key || $0.name.localizedCaseInsensitiveCompare(template.name) == .orderedSame
            }
            guard let closest = candidates.min(by: { abs($0.amount - template.amount) < abs($1.amount - template.amount) })
            else { continue }
            matchedSuggestions.insert(closest.id)
            let difference = abs(closest.amount - template.amount)
            if difference > max(2, template.amount * 0.05) && difference < template.amount * 0.6 {
                changes.append(FixedCostChange(id: template.key, template: template, newAmount: closest.amount))
            }
        }

        let newPayments = suggestions.filter { suggestion in
            !matchedSuggestions.contains(suggestion.id)
                && !templates.contains { MerchantKey.make($0.name) == suggestion.merchantKey }
                && (!suggestion.amountVaries || suggestion.count >= 5)
        }
        return (changes, newPayments)
    }

    /// Cost per year of a default fixed cost.
    static func yearlyAmount(_ template: FixedCostTemplate) -> Double {
        switch template.frequency {
        case .weekly: return template.amount * 52
        case .monthly: return template.amount * 12
        case .quarterly: return template.amount * 4
        case .yearly: return template.amount
        }
    }
}

// MARK: - Notifications

@MainActor
enum Notifications {
    enum Kind: String, CaseIterable {
        case payday = "notifyPayday"
        case budget = "notifyBudget"
        case weekly = "notifyWeekly"
        case fixedCostChanges = "notifyFixedCostChanges"
    }

    private static let sentBudgetAlertsKey = "sentBudgetAlerts"

    static func isEnabled(_ kind: Kind) -> Bool {
        UserDefaults.standard.bool(forKey: kind.rawValue)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Plans the payday reminder and the weekly summary (with today's numbers).
    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["payday", "weekly-summary"])

        let periods = (try? context.fetch(FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        guard let current = periods.last(where: { $0.isCurrent }) else { return }
        let calendar = Calendar.current

        if isEnabled(.payday) {
            var components = calendar.dateComponents([.year, .month, .day], from: current.endDate)
            components.hour = 9
            let content = UNMutableNotificationContent()
            content.title = "It's payday"
            content.body = "Open Budget to check your income and fixed costs for the new period."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "payday", content: content, trigger: trigger))
        }

        if isEnabled(.weekly) {
            let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
            let left = PeriodManager.leftToSpend(in: current, expenses: expenses)
            let days = PeriodManager.daysLeft(in: current)
            var components = DateComponents()
            components.weekday = 1  // Sunday
            components.hour = 18
            let content = UNMutableNotificationContent()
            content.title = "Your week in Budget"
            content.body = left > 0
                ? "\(left.asCurrency) left for \(days) days, about \((left / Double(max(days, 1))).asCurrency) a day."
                : "You're \((-left).asCurrency) over for this period."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "weekly-summary", content: content, trigger: trigger))
        }
    }

    /// Sends one alert per category per period when 80% and when 100% of the budget is used.
    static func checkBudgets(context: ModelContext) {
        guard isEnabled(.budget) else { return }
        let periods = (try? context.fetch(FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        guard let current = periods.last(where: { $0.isCurrent }) else { return }
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []

        let defaults = UserDefaults.standard
        var sent = Set(defaults.stringArray(forKey: sentBudgetAlertsKey) ?? [])
        let periodKey = String(Int(current.startDate.timeIntervalSince1970))

        for category in categories where category.budget > 0 {
            let budget = PeriodManager.effectiveBudget(category: category, period: current,
                                                       periods: periods, expenses: expenses)
            guard budget > 0 else { continue }
            let spent = PeriodManager.spent(in: current, category: category, expenses: expenses)
            let ratio = spent / budget
            let level = ratio >= 1 ? 100 : (ratio >= 0.8 ? 80 : 0)
            guard level > 0 else { continue }
            let key = "\(periodKey)|\(category.name)|\(level)"
            guard !sent.contains(key) else { continue }
            sent.insert(key)
            if level == 100 {
                send(id: key, title: "\(category.name): budget used up",
                     body: "You've spent \(spent.asCurrency) of \(budget.asCurrency) this period.")
            } else {
                send(id: key, title: "\(category.name): 80% of your budget",
                     body: "\((budget - spent).asCurrency) left of \(budget.asCurrency) this period.")
            }
        }
        defaults.set(Array(sent.suffix(500)), forKey: sentBudgetAlertsKey)
    }
}

// MARK: - Forecast, trends and insights

enum Insights {
    /// Where you'll end up if you keep spending at the current pace. Nil early in the period.
    static func forecast(period: BudgetPeriod, spent: Double) -> (spent: Double, left: Double)? {
        guard period.isCurrent else { return nil }
        let calendar = Calendar.current
        let totalDays = calendar.dateComponents([.day], from: period.startDate, to: period.endDate).day ?? 0
        let elapsed = (calendar.dateComponents([.day], from: period.startDate,
                                                to: calendar.startOfDay(for: .now)).day ?? 0) + 1
        guard elapsed >= 3, totalDays > elapsed else { return nil }
        let projected = spent / Double(elapsed) * Double(totalDays)
        return (projected, period.totalIncome - period.totalFixedCosts - projected)
    }

    /// Share of the period that has passed (0...1).
    static func elapsedFraction(of period: BudgetPeriod) -> Double {
        let total = period.endDate.timeIntervalSince(period.startDate)
        guard total > 0 else { return 1 }
        return min(max(Date.now.timeIntervalSince(period.startDate) / total, 0), 1)
    }

    /// Short messages like "Dining out: on track for €210, 40% more than usual (€150)".
    static func categoryInsights(current: BudgetPeriod, periods: [BudgetPeriod],
                                 expenses: [Expense], categories: [BudgetCategory]) -> [String] {
        let fraction = elapsedFraction(of: current)
        guard !current.isCurrent || fraction >= 0.25 else { return [] }
        let previous = Array(periods.filter { $0.startDate < current.startDate }.suffix(6))
        guard previous.count >= 2 else { return [] }

        var results: [(difference: Double, text: String)] = []
        for category in categories {
            let history = previous.map { PeriodManager.spent(in: $0, category: category, expenses: expenses) }
            let average = history.reduce(0, +) / Double(history.count)
            guard average >= 20 else { continue }
            let spentNow = PeriodManager.spent(in: current, category: category, expenses: expenses)
            let expected = current.isCurrent ? spentNow / max(fraction, 0.01) : spentNow
            let change = (expected - average) / average
            guard abs(change) >= 0.3, abs(expected - average) >= 20 else { continue }
            let percent = Int((abs(change) * 100).rounded())
            let prefix = current.isCurrent ? "on track for" : "spent"
            let text = change > 0
                ? "\(category.name): \(prefix) \(expected.asCurrency), \(percent)% more than usual (\(average.asCurrency))"
                : "\(category.name): \(prefix) \(expected.asCurrency), \(percent)% less than usual (\(average.asCurrency))"
            results.append((abs(expected - average), text))
        }
        return results.sorted { $0.difference > $1.difference }.prefix(3).map { $0.text }
    }
}

// MARK: - Savings goals

enum GoalMath {
    /// Saved so far: money added by hand plus the linked savings fixed cost in every period since the goal started.
    static func progress(of goal: SavingsGoal, periods: [BudgetPeriod]) -> Double {
        guard !goal.linkedSavingsKey.isEmpty else { return goal.savedAmount }
        let goalStart = periods.last(where: { $0.startDate <= goal.createdAt })?.startDate ?? goal.createdAt
        var linked = 0.0
        for period in periods where period.startDate >= goalStart && period.startDate <= .now {
            for cost in period.fixedCosts ?? [] where cost.templateKey == goal.linkedSavingsKey {
                linked += cost.amount
            }
        }
        return goal.savedAmount + linked
    }

    /// How much to put aside per period to reach the goal by its deadline.
    static func neededPerPeriod(for goal: SavingsGoal, progress: Double) -> Double? {
        guard let deadline = goal.deadline, deadline > .now else { return nil }
        let remaining = goal.targetAmount - progress
        guard remaining > 0 else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: .now, to: deadline).month ?? 0
        return remaining / Double(max(months, 1))
    }
}
