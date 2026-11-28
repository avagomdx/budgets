import SwiftUI
import SwiftData
import UIKit

/// Quickly add an expense, or edit an existing one.
struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @AppStorage("lastCategoryName") private var lastCategoryName = ""

    private let expense: Expense?

    @State private var amountText: String
    @State private var date: Date
    @State private var note: String
    @State private var selectedCategory: BudgetCategory?
    @State private var receiptData: Data?
    @State private var didLoadReceipt = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    init(expense: Expense? = nil) {
        self.expense = expense
        _amountText = State(initialValue: expense?.amount.editableAmount ?? "")
        _date = State(initialValue: expense?.date ?? .now)
        _note = State(initialValue: expense?.note ?? "")
        _selectedCategory = State(initialValue: expense?.category)
    }

    private var isEditing: Bool { expense != nil }
    private var amount: Double? { amountText.parsedAmount }
    private var canSave: Bool { amount != nil && selectedCategory != nil }

    var body: some View {
        NavigationStack {
            Form {
                // Amount
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(AppFormat.currencySymbol)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField(0.0.editableAmount, text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .focused($amountFocused)
                    }
                    .padding(.vertical, 4)
                }

                // Category
                Section {
                    if categories.isEmpty {
                        Text("Create a category in Settings first.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                            ForEach(categories) { category in
                                categoryChip(category)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Category")
                }

                // Date (defaults to today)
                Section {
                    HStack(spacing: 8) {
                        dayChip("Today", daysAgo: 0)
                        dayChip("Yesterday", daysAgo: 1)
                        Spacer(minLength: 4)
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                } header: {
                    Text("Date")
                }

                // Note
                Section {
                    TextField("e.g. Supermarket", text: $note)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                } header: {
                    Text("Note (optional)")
                }

                ReceiptSection(data: $receiptData)

                if isEditing {
                    Section {
                        Button("Delete expense", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit expense" : "New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteExpense() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                if !didLoadReceipt {
                    didLoadReceipt = true
                    if let expense, expense.hasReceipt {
                        receiptData = expense.receiptData
                    }
                }
            }
            .task {
                if selectedCategory == nil {
                    selectedCategory = categories.first { $0.name == lastCategoryName } ?? categories.first
                }
                if !isEditing {
                    // Small delay so the keyboard opens cleanly after the sheet animation.
                    try? await Task.sleep(for: .milliseconds(350))
                    amountFocused = true
                }
            }
        }
    }

    // MARK: - Parts

    private func categoryChip(_ category: BudgetCategory) -> some View {
        let isSelected = selectedCategory?.persistentModelID == category.persistentModelID
        return Button {
            selectedCategory = category
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                CategoryIcon(category: category, size: 40)
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? category.color.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? category.color : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayChip(_ title: String, daysAgo: Int) -> some View {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let isSelected = calendar.isDate(date, inSameDayAs: target)
        return Button {
            date = target
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemFill),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func save() {
        guard let amount, let selectedCategory else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let expense {
            expense.amount = amount
            expense.date = date
            expense.note = trimmedNote
            expense.category = selectedCategory
            expense.needsReview = false
            expense.receiptData = receiptData
            expense.hasReceipt = receiptData != nil
        } else {
            let newExpense = Expense(amount: amount, date: date, note: trimmedNote, category: nil)
            context.insert(newExpense)
            newExpense.category = selectedCategory
            newExpense.receiptData = receiptData
            newExpense.hasReceipt = receiptData != nil
        }
        try? context.save()
        Notifications.checkBudgets(context: context)
        lastCategoryName = selectedCategory.name
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteExpense() {
        if let expense {
            context.delete(expense)
            try? context.save()
        }
        dismiss()
    }
}
