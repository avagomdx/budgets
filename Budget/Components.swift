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

/// Maandkiezer: ‹ November 2026 ›  (tik op de maand om terug te gaan naar nu)
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

/// Voortgangsbalk voor besteed vs. budget.
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
                        Text("\((spent - budget).euro) te veel")
                            .foregroundStyle(.red)
                    } else {
                        Text("Nog \((budget - spent).euro)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("van \(budget.euro)")
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
    /// Toon de datum i.p.v. de categorie als subtitel (handig in categorie-detail).
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: expense.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? (expense.category?.name ?? "Uitgave") : expense.note)
                    .lineLimit(1)
                Text(showDate ? expense.date.dayTitle : (expense.category?.name ?? "Zonder categorie"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.amount.euro)
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
            Label("Uitgave toevoegen", systemImage: "plus")
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
