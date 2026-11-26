import SwiftUI
import SwiftData
import UIKit

/// Snel een uitgave toevoegen, of een bestaande bewerken.
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
                // Bedrag
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("€")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .focused($amountFocused)
                    }
                    .padding(.vertical, 4)
                }

                // Categorie
                Section {
                    if categories.isEmpty {
                        Text("Maak eerst een categorie aan bij Instellingen.")
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
                    Text("Categorie")
                }

                // Datum (standaard vandaag)
                Section {
                    HStack(spacing: 8) {
                        dayChip("Vandaag", daysAgo: 0)
                        dayChip("Gisteren", daysAgo: 1)
                        Spacer(minLength: 4)
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                } header: {
                    Text("Datum")
                }

                // Notitie
                Section {
                    TextField("Bijv. Albert Heijn", text: $note)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                } header: {
                    Text("Notitie (optioneel)")
                }

                if isEditing {
                    Section {
                        Button("Verwijder uitgave", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Uitgave bewerken" : "Nieuwe uitgave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Gereed") { amountFocused = false }
                }
            }
            .confirmationDialog("Deze uitgave verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verwijder", role: .destructive) { deleteExpense() }
                Button("Annuleer", role: .cancel) {}
            }
            .task {
                if selectedCategory == nil {
                    selectedCategory = categories.first { $0.name == lastCategoryName } ?? categories.first
                }
                if !isEditing {
                    // Kleine vertraging zodat het toetsenbord netjes opent na de sheet-animatie.
                    try? await Task.sleep(for: .milliseconds(350))
                    amountFocused = true
                }
            }
        }
    }

    // MARK: - Onderdelen

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

    // MARK: - Acties

    private func save() {
        guard let amount, let selectedCategory else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let expense {
            expense.amount = amount
            expense.date = date
            expense.note = trimmedNote
            expense.category = selectedCategory
        } else {
            context.insert(Expense(amount: amount, date: date, note: trimmedNote, category: selectedCategory))
        }
        try? context.save()
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
