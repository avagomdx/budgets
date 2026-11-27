import SwiftUI
import SwiftData
import UIKit

/// Create or edit a category (name, budget, color, icon).
struct CategoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]

    private let category: BudgetCategory?

    @State private var name: String
    @State private var icon: String
    @State private var colorName: String
    @State private var budgetText: String
    @State private var carryOver: Bool

    init(category: BudgetCategory?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "tag")
        _colorName = State(initialValue: category?.colorName ?? "blue")
        let budget = category?.budget ?? 0
        _budgetText = State(initialValue: budget > 0 ? budget.editableAmount : "")
        _carryOver = State(initialValue: category?.carryOver ?? false)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// nil = invalid input; empty field = 0 (no budget)
    private var budget: Double? {
        let text = budgetText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 0 }
        return text.parsedAmount
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && budget != nil
    }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    CategoryIcon(icon: icon, color: CategoryPalette.color(named: colorName), size: 44)
                    TextField("Name", text: $name)
                        .font(.title3)
                }
            }

            Section {
                HStack {
                    Text(AppFormat.currencySymbol).foregroundStyle(.secondary)
                    TextField("No budget", text: $budgetText)
                        .keyboardType(.decimalPad)
                }
                Toggle("Carry over what's left", isOn: $carryOver)
            } header: {
                Text("Budget per period")
            } footer: {
                Text("Leave empty if you don't want to track a budget for this category. Carry over: what's left (or overspent) moves to the next period.")
            }

            Section {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(CategoryPalette.colors) { item in
                        Button {
                            colorName = item.name
                        } label: {
                            Circle()
                                .fill(item.color.gradient)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if item.name == colorName {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Color")
            }

            Section {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(CategoryPalette.icons, id: \.self) { symbol in
                        let isSelected = symbol == icon
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 42, height: 42)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(isSelected ? CategoryPalette.color(named: colorName) : Color(uiColor: .secondarySystemFill),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Icon")
            }
        }
        .navigationTitle(category == nil ? "New category" : "Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard let budget, !trimmedName.isEmpty else { return }
        if let category {
            category.name = trimmedName
            category.icon = icon
            category.colorName = colorName
            category.budget = budget
            category.carryOver = carryOver
        } else {
            let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
            context.insert(BudgetCategory(name: trimmedName, icon: icon, colorName: colorName,
                                          budget: budget, carryOver: carryOver, sortOrder: nextOrder))
        }
        try? context.save()
        dismiss()
    }
}
