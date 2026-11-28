import SwiftUI
import SwiftData

// MARK: - Transactions to check (added by the automatic sync)

struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Expense> { $0.needsReview == true }, sort: \Expense.date, order: .reverse)
    private var items: [Expense]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query private var rules: [CategoryRule]

    private struct RuleOffer: Identifiable {
        let id = UUID()
        let pattern: String
        let merchant: String
        let category: BudgetCategory
    }

    @State private var ruleOffer: RuleOffer?
    @State private var isSyncing = false

    var body: some View {
        List {
            Section {
                Text("New payments from your bank. Check the category and tap ✓. Swipe left on anything that isn't an expense, like a transfer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                ContentUnavailableView("All checked", systemImage: "checkmark.circle",
                                       description: Text("New bank payments will show up here."))
                    .listRowBackground(Color.clear)
            }

            ForEach(items) { expense in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(expense.note.isEmpty ? "Bank payment" : expense.note)
                            .lineLimit(1)
                        Text("\(expense.date.dayTitle) · \(expense.amount.asCurrency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        categoryMenu(for: expense)
                    }
                    Spacer()
                    Button {
                        confirm(expense)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Confirm")
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                for index in offsets {
                    let expense = items[index]
                    BankSync.dismiss(externalID: expense.externalID)
                    context.delete(expense)
                }
                try? context.save()
            }
        }
        .navigationTitle("To check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Confirm all") {
                    for expense in items {
                        expense.needsReview = false
                    }
                    try? context.save()
                }
                .disabled(items.isEmpty)
            }
        }
        .refreshable {
            await BankSync.syncIfNeeded(context: context, force: true)
        }
        .confirmationDialog(ruleOffer.map { "Always put \($0.merchant) in \($0.category.name)?" } ?? "",
                            isPresented: Binding(get: { ruleOffer != nil }, set: { if !$0 { ruleOffer = nil } }),
                            titleVisibility: .visible,
                            presenting: ruleOffer) { offer in
            Button("Always") {
                addRule(offer)
            }
            Button("Only this one", role: .cancel) {
                ruleOffer = nil
            }
        }
    }

    private func categoryMenu(for expense: Expense) -> some View {
        Menu {
            Button("None") {
                expense.category = nil
                try? context.save()
            }
            ForEach(categories) { category in
                Button {
                    change(expense, to: category)
                } label: {
                    Label(category.name, systemImage: category.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let category = expense.category {
                    CategoryIcon(category: category, size: 20)
                    Text(category.name)
                } else {
                    Text("Choose category")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
        }
    }

    private func change(_ expense: Expense, to category: BudgetCategory) {
        let previous = expense.category?.persistentModelID
        expense.category = category
        try? context.save()
        let pattern = MerchantKey.make(expense.note)
        let alreadyRule = rules.contains { $0.pattern == pattern && $0.category?.persistentModelID == category.persistentModelID }
        if previous != category.persistentModelID, !pattern.isEmpty, !alreadyRule {
            ruleOffer = RuleOffer(pattern: pattern, merchant: expense.note, category: category)
        }
    }

    private func confirm(_ expense: Expense) {
        expense.needsReview = false
        try? context.save()
    }

    private func addRule(_ offer: RuleOffer) {
        for rule in rules where rule.pattern == offer.pattern {
            context.delete(rule)
        }
        let rule = CategoryRule(pattern: offer.pattern)
        context.insert(rule)
        rule.category = offer.category

        // Apply it to the other payments in this list too.
        for expense in items where MerchantKey.make(expense.note) == offer.pattern {
            expense.category = offer.category
        }
        try? context.save()
        ruleOffer = nil
    }
}

/// Banner that links to the review list when there's something to check.
struct ReviewBanner: View {
    let count: Int

    private var title: String {
        count == 1 ? "1 new payment to check" : "\(count) new payments to check"
    }

    var body: some View {
        NavigationLink {
            ReviewView()
        } label: {
            Label(title, systemImage: "tray.full")
                .foregroundStyle(.orange)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Category rules

struct RulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CategoryRule.pattern) private var rules: [CategoryRule]
    @State private var adding = false

    var body: some View {
        List {
            Section {
                if rules.isEmpty {
                    Text("No rules yet. When you change a category in \"To check\", the app offers to make a rule.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contains \"\(rule.pattern)\"")
                            Text(rule.category?.name ?? "No category")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let category = rule.category {
                            CategoryIcon(category: category, size: 26)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(rules[index])
                    }
                    try? context.save()
                }

                Button {
                    adding = true
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
            } footer: {
                Text("Rules go before the built-in shop list. They're used for imported and synced payments, and by Auto-categorize.")
            }
        }
        .navigationTitle("Category rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $adding) {
            RuleEditView()
        }
    }
}

struct RuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var pattern = ""
    @State private var category: BudgetCategory?

    private var canSave: Bool {
        !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. tikkie jan", text: $pattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    CategoryPickerRow(selection: $category)
                } footer: {
                    Text("Payments whose name or description contains this text get this category.")
                }
            }
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let rule = CategoryRule(pattern: pattern)
                        context.insert(rule)
                        rule.category = category
                        try? context.save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
