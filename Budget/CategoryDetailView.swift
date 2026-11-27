import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let category: BudgetCategory
    let period: BudgetPeriod

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @State private var editing: Expense?

    var body: some View {
        let id = category.persistentModelID
        let items = expenses.filter {
            $0.category?.persistentModelID == id && period.contains($0.date)
        }
        let spent = items.reduce(0) { $0 + $1.amount }
        let budget = PeriodManager.effectiveBudget(category: category, period: period,
                                                   periods: periods, expenses: expenses)

        List {
            Section {
                HStack(spacing: 12) {
                    CategoryIcon(category: category, size: 44)
                    VStack(alignment: .leading) {
                        Text("Spent").font(.caption).foregroundStyle(.secondary)
                        Text(spent.asCurrency)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                }
                BudgetBar(spent: spent, budget: budget, color: category.color)
            } header: {
                Text(AppFormat.periodTitle(start: period.startDate, lastDay: period.lastDay))
            }

            Section {
                if items.isEmpty {
                    Text("No expenses in this period")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { expense in
                    Button {
                        editing = expense
                    } label: {
                        ExpenseRow(expense: expense, showDate: true)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(items[index])
                    }
                }
            } header: {
                Text("Expenses")
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { expense in
            ExpenseFormView(expense: expense)
        }
    }
}
