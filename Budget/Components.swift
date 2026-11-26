import SwiftUI
import UIKit

struct CategoryIcon: View {
    let icon: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

extension CategoryIcon {
    init(category: BudgetCategory?, size: CGFloat = 34) {
        self.init(icon: category?.icon ?? "questionmark",
                  color: category?.color ?? .gray,
                  size: size)
    }
}

/// Month switcher: ‹ November 2026 ›  (tap the month to jump back to the current month)
struct MonthSwitcher: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button {
                month = month.addingMonths(-1)
            } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                month = .now
            } label: {
                Text(month.monthTitle).font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                month = month.addingMonths(1)
            } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// Progress bar for spent vs. budget.
struct BudgetBar: View {
    let spent: Double
    let budget: Double
    let color: Color

    private var isOver: Bool { spent > budget }

    var body: some View {
        if budget > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: min(spent, budget), total: budget)
                    .tint(isOver ? .red : color)
                HStack {
                    if isOver {
                        Text("\((spent - budget).asCurrency) over")
                            .foregroundStyle(.red)
                    } else {
                        Text("\((budget - spent).asCurrency) left")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("of \(budget.asCurrency)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    /// Show the date instead of the category as subtitle (useful in category detail).
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: expense.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? (expense.category?.name ?? "Expense") : expense.note)
                    .lineLimit(1)
                Text(showDate ? expense.date.dayTitle : (expense.category?.name ?? "No category"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.amount.asCurrency)
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .contentShape(Rectangle())
    }
}

struct AddExpenseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add expense", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
