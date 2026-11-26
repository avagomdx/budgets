import SwiftUI
import SwiftData

struct OverviewView: View {
    @Binding var showingAdd: Bool

    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var month = Date.now

    var body: some View {
        let monthExpenses = expenses.filter { $0.date.isSameMonth(as: month) }
        let spentByCategory = Self.totals(for: monthExpenses)
        let totalSpent = monthExpenses.reduce(0) { $0 + $1.amount }
        let totalBudget = categories.reduce(0) { $0 + $1.monthlyBudget }

        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $month)
                }

                Section {
                    SummaryCard(spent: totalSpent, budget: totalBudget, month: month)
                }

                Section {
                    ForEach(categories) { category in
                        NavigationLink {
                            CategoryDetailView(category: category, month: $month)
                        } label: {
                            BudgetRow(category: category,
                                      spent: spentByCategory[category.persistentModelID] ?? 0)
                        }
                    }
                } header: {
                    Text("Budgetten")
                }

                if !monthExpenses.isEmpty {
                    Section {
                        ForEach(monthExpenses.prefix(5)) { expense in
                            ExpenseRow(expense: expense, showDate: true)
                        }
                    } header: {
                        Text("Laatste uitgaven")
                    }
                }
            }
            .navigationTitle("Overzicht")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Uitgave toevoegen")
                }
            }
            .safeAreaInset(edge: .bottom) {
                AddExpenseButton { showingAdd = true }
            }
        }
    }

    static func totals(for expenses: [Expense]) -> [PersistentIdentifier: Double] {
        var result: [PersistentIdentifier: Double] = [:]
        for expense in expenses {
            if let id = expense.category?.persistentModelID {
                result[id, default: 0] += expense.amount
            }
        }
        return result
    }
}

private struct SummaryCard: View {
    let spent: Double
    let budget: Double
    let month: Date

    private var remaining: Double { budget - spent }

    /// Wat je nog per dag kunt uitgeven, alleen voor de huidige maand.
    private var perDay: Double? {
        guard month.isSameMonth(as: .now), remaining > 0 else { return nil }
        let calendar = Calendar.current
        guard let days = calendar.range(of: .day, in: .month, for: .now)?.count else { return nil }
        let today = calendar.component(.day, from: .now)
        let daysLeft = max(days - today + 1, 1)
        return remaining / Double(daysLeft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uitgegeven")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(spent.euro)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            BudgetBar(spent: spent, budget: budget, color: .accentColor)

            if let perDay {
                Label("Ongeveer \(perDay.euro) per dag voor de rest van de maand",
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .animation(.default, value: spent)
    }
}

private struct BudgetRow: View {
    let category: BudgetCategory
    let spent: Double

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.name)
                    Spacer()
                    Text(spent.euro)
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(category.monthlyBudget > 0 && spent > category.monthlyBudget ? Color.red : Color.primary)
                }
                BudgetBar(spent: spent, budget: category.monthlyBudget, color: category.color)
            }
        }
        .padding(.vertical, 4)
    }
}
