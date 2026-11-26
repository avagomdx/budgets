import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let category: BudgetCategory
    @Binding var month: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var editing: Expense?

    var body: some View {
        let items = expenses.filter {
            $0.category?.persistentModelID == category.persistentModelID && $0.date.isSameMonth(as: month)
        }
        let spent = items.reduce(0) { $0 + $1.amount }

        List {
            Section {
                MonthSwitcher(month: $month)
            }

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
                BudgetBar(spent: spent, budget: category.monthlyBudget, color: category.color)
            }

            Section {
                if items.isEmpty {
                    Text("No expenses this month")
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
