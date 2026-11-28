import AppIntents
import SwiftData

/// "Hey Siri, add an expense in Budget" — also usable from Shortcuts and the Action button.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add expense"
    static let description = IntentDescription("Adds an expense to Budget, dated today.")

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category", description: "Name of one of your categories, e.g. Groceries.")
    var categoryName: String?

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(BudgetApp.container)
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let rules = (try? context.fetch(FetchDescriptor<CategoryRule>())) ?? []

        var category: BudgetCategory?
        if let wanted = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines), !wanted.isEmpty {
            category = categories.first { $0.name.localizedCaseInsensitiveCompare(wanted) == .orderedSame }
                ?? categories.first { $0.name.localizedCaseInsensitiveContains(wanted) }
        }
        let text = note ?? ""
        if category == nil, !text.isEmpty {
            category = AutoCategory.suggest(for: text, in: categories, rules: rules)
        }

        let rounded = (abs(amount) * 100).rounded() / 100
        let expense = Expense(amount: rounded, date: .now, note: text, category: nil)
        context.insert(expense)
        expense.category = category
        try context.save()
        Notifications.checkBudgets(context: context)

        let message: String
        if let category {
            message = "Added \(rounded.asCurrency) to \(category.name)."
        } else {
            message = "Added \(rounded.asCurrency). You can pick a category in the app."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// "Hey Siri, how much can I spend in Budget?"
struct LeftToSpendIntent: AppIntent {
    static let title: LocalizedStringResource = "Left to spend"
    static let description = IntentDescription("Tells you how much is left to spend this period.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(BudgetApp.container)
        let periods = (try? context.fetch(FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []

        let message: String
        if let current = periods.last(where: { $0.isCurrent }) {
            let left = PeriodManager.leftToSpend(in: current, expenses: expenses)
            let days = PeriodManager.daysLeft(in: current)
            message = left > 0
                ? "You have \(left.asCurrency) left for \(days) days, about \((left / Double(days)).asCurrency) a day."
                : "You're \((-left).asCurrency) over budget this period."
        } else {
            message = "Open Budget to set up your first period."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct BudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add an expense in \(.applicationName)",
                              "Add expense to \(.applicationName)",
                              "New expense in \(.applicationName)"],
                    shortTitle: "Add expense",
                    systemImageName: "plus.circle")
        AppShortcut(intent: LeftToSpendIntent(),
                    phrases: ["How much can I spend in \(.applicationName)",
                              "What's left in \(.applicationName)"],
                    shortTitle: "Left to spend",
                    systemImageName: "eurosign.circle")
    }
}
