import SwiftUI
import SwiftData
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

/// Period switcher: ‹ 20 Nov – 19 Dec ›  (tap the title to jump back to the current period)
struct PeriodSwitcher: View {
    let periods: [BudgetPeriod]
    @Binding var selectedID: PersistentIdentifier?

    private var selected: BudgetPeriod? {
        PeriodManager.resolve(selectedID, in: periods)
    }

    private var selectedIndex: Int? {
        guard let selected else { return nil }
        return periods.firstIndex { $0.persistentModelID == selected.persistentModelID }
    }

    var body: some View {
        HStack {
            Button {
                if let index = selectedIndex, index > 0 {
                    selectedID = periods[index - 1].persistentModelID
                }
            } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .buttonStyle(.borderless)
            .disabled((selectedIndex ?? 0) == 0)

            Spacer()

            Button {
                selectedID = nil
            } label: {
                VStack(spacing: 2) {
                    if let selected {
                        Text(AppFormat.periodTitle(start: selected.startDate, lastDay: selected.lastDay))
                            .font(.headline)
                        Text(selected.isCurrent ? "Current period" : "Tap for current period")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No period").font(.headline)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                if let index = selectedIndex, index < periods.count - 1 {
                    selectedID = periods[index + 1].persistentModelID
                }
            } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .buttonStyle(.borderless)
            .disabled((selectedIndex ?? periods.count) >= periods.count - 1)
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
                ProgressView(value: min(max(spent, 0), budget), total: budget)
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

/// A label + amount row, e.g. "Income   + € 3,000.00"
struct AmountRow: View {
    let title: String
    var subtitle: String? = nil
    let amount: Double
    var sign: String = ""
    var color: Color = .primary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(sign + amount.asCurrency)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

/// Text field for amounts with the currency symbol in front.
struct AmountField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(AppFormat.currencySymbol)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
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
