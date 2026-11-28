import SwiftUI
import SwiftData

// MARK: - Edit targets

enum IncomeEditTarget: Identifiable {
    case edit(IncomeEntry)
    case add(extra: Bool)

    var id: String {
        switch self {
        case .edit(let entry): return "edit-\(entry.persistentModelID.hashValue)"
        case .add(let extra): return extra ? "add-extra" : "add-regular"
        }
    }
}

enum FixedCostEditTarget: Identifiable {
    case edit(PeriodFixedCost)
    case add

    var id: String {
        switch self {
        case .edit(let cost): return "edit-\(cost.persistentModelID.hashValue)"
        case .add: return "add"
        }
    }
}

// MARK: - Sections (used on the period screens and in the check-in)

struct PeriodIncomeSections: View {
    let period: BudgetPeriod
    var showsExtra = true
    let onSelect: (IncomeEditTarget) -> Void

    var body: some View {
        let entries = period.sortedIncomes
        let regular = entries.filter { !$0.isExtra }
        let extra = entries.filter { $0.isExtra }

        Section {
            ForEach(regular) { entry in
                Button {
                    onSelect(.edit(entry))
                } label: {
                    AmountRow(title: entry.name, amount: entry.amount)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                onSelect(.add(extra: false))
            } label: {
                Label("Add income", systemImage: "plus")
            }
        } header: {
            Text("Income")
        } footer: {
            Text("Total income: \(period.totalIncome.asCurrency)")
        }

        if showsExtra {
            Section {
                ForEach(extra) { entry in
                    Button {
                        onSelect(.edit(entry))
                    } label: {
                        AmountRow(title: entry.name, subtitle: entry.date.dayTitle, amount: entry.amount, sign: "+ ")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    onSelect(.add(extra: true))
                } label: {
                    Label("Add extra income", systemImage: "plus")
                }
            } header: {
                Text("Extra income")
            } footer: {
                Text("Refunds, Tikkies and other money that comes in during the period. It's added to what you have left to spend.")
            }
        }
    }
}

struct PeriodFixedCostSections: View {
    let period: BudgetPeriod
    let onSelect: (FixedCostEditTarget) -> Void

    var body: some View {
        let costs = period.sortedFixedCosts
        let regular = costs.filter { !$0.isSavings }
        let savings = costs.filter { $0.isSavings }

        Section {
            ForEach(regular) { cost in
                row(for: cost)
            }
            Button {
                onSelect(.add)
            } label: {
                Label("Add a fixed cost", systemImage: "plus")
            }
        } header: {
            Text("Fixed costs")
        } footer: {
            Text("Changes here only apply to this period. Your defaults for new periods are in Settings.")
        }

        if !savings.isEmpty {
            Section {
                ForEach(savings) { cost in
                    row(for: cost)
                }
            } header: {
                Text("Savings")
            }
        }

        Section {
            AmountRow(title: "Total fixed costs", amount: period.totalFixedCosts)
                .fontWeight(.semibold)
        }
    }

    private func row(for cost: PeriodFixedCost) -> some View {
        Button {
            onSelect(.edit(cost))
        } label: {
            AmountRow(title: cost.name, subtitle: cost.detail, amount: cost.amount)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Period screens

struct PeriodIncomeView: View {
    let period: BudgetPeriod
    @State private var target: IncomeEditTarget?

    var body: some View {
        List {
            PeriodIncomeSections(period: period) { target = $0 }
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $target) { target in
            IncomeEntryEditView(period: period, target: target)
        }
    }
}

struct PeriodFixedCostsView: View {
    @Environment(\.modelContext) private var context
    let period: BudgetPeriod
    @State private var target: FixedCostEditTarget?
    @State private var resultMessage: String?

    var body: some View {
        List {
            PeriodFixedCostSections(period: period) { target = $0 }

            Section {
                Button {
                    let added = PeriodManager.addMissingDefaultFixedCosts(to: period, context: context)
                    resultMessage = added == 0
                        ? "All your default fixed costs are already in this period."
                        : "Added \(added) fixed \(added == 1 ? "cost" : "costs") from your defaults."
                } label: {
                    Label("Add missing defaults", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Adds default fixed costs (Settings) that aren't in this period yet.")
            }
        }
        .alert("Fixed costs",
               isPresented: Binding(get: { resultMessage != nil },
                                    set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .navigationTitle("Fixed costs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $target) { target in
            PeriodFixedCostEditView(period: period, target: target)
        }
    }
}

// MARK: - Edit sheets

struct IncomeEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var sources: [IncomeSource]

    let period: BudgetPeriod
    private let entry: IncomeEntry?
    private let isExtra: Bool

    @State private var name: String
    @State private var amountText: String
    @State private var date: Date
    @State private var updateDefault = false

    init(period: BudgetPeriod, target: IncomeEditTarget) {
        self.period = period
        switch target {
        case .edit(let entry):
            self.entry = entry
            self.isExtra = entry.isExtra
            _name = State(initialValue: entry.name)
            _amountText = State(initialValue: entry.amount.editableAmountOrEmpty)
            _date = State(initialValue: entry.date)
        case .add(let extra):
            self.entry = nil
            self.isExtra = extra
            _name = State(initialValue: "")
            _amountText = State(initialValue: "")
            _date = State(initialValue: period.isCurrent ? Date.now : period.startDate)
        }
    }

    private var linkedSource: IncomeSource? {
        guard let key = entry?.sourceKey, !key.isEmpty else { return nil }
        return sources.first { $0.key == key }
    }

    private var amount: Double? { amountText.parsedNonNegativeAmount }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isExtra ? "e.g. Refund" : "e.g. Salary", text: $name)
                    AmountField(placeholder: "0.00", text: $amountText)
                    if isExtra {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }

                if linkedSource != nil {
                    Section {
                        Toggle("Also use for future periods", isOn: $updateDefault)
                    } footer: {
                        Text("Updates your default income, so new periods start with this amount.")
                    }
                }

                if entry != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let entry {
                                context.delete(entry)
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isExtra ? "Extra income" : "Income")
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
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.name = trimmed
            entry.amount = amount
            if isExtra { entry.date = date }
            if updateDefault, let source = linkedSource {
                source.amount = amount
                source.name = trimmed
            }
        } else {
            let order = (period.incomes ?? []).map(\.sortOrder).max() ?? 0
            let newEntry = IncomeEntry(name: trimmed, amount: amount, isExtra: isExtra,
                                       date: isExtra ? date : period.startDate,
                                       sortOrder: order + 1, sourceKey: "")
            context.insert(newEntry)
            newEntry.period = period
        }
        try? context.save()
        dismiss()
    }
}

struct PeriodFixedCostEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var templates: [FixedCostTemplate]

    let period: BudgetPeriod
    private let cost: PeriodFixedCost?

    @State private var name: String
    @State private var amountText: String
    @State private var isSavings: Bool
    @State private var category: BudgetCategory?
    @State private var updateDefault = false

    init(period: BudgetPeriod, target: FixedCostEditTarget) {
        self.period = period
        switch target {
        case .edit(let cost):
            self.cost = cost
            _name = State(initialValue: cost.name)
            _amountText = State(initialValue: cost.amount.editableAmountOrEmpty)
            _isSavings = State(initialValue: cost.isSavings)
            _category = State(initialValue: cost.category)
        case .add:
            self.cost = nil
            _name = State(initialValue: "")
            _amountText = State(initialValue: "")
            _isSavings = State(initialValue: false)
            _category = State(initialValue: nil)
        }
    }

    /// The default this cost came from, only when it's a monthly one (others are calculated per period).
    private var linkedMonthlyTemplate: FixedCostTemplate? {
        guard let key = cost?.templateKey, !key.isEmpty else { return nil }
        guard let template = templates.first(where: { $0.key == key }), template.frequency == .monthly else { return nil }
        return template
    }

    private var amount: Double? { amountText.parsedAmount }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    AmountField(placeholder: "0.00", text: $amountText)
                    Toggle("This is savings", isOn: $isSavings)
                    CategoryPickerRow(selection: $category)
                } footer: {
                    if let detail = cost?.detail, !detail.isEmpty {
                        Text(detail)
                    }
                }

                if linkedMonthlyTemplate != nil {
                    Section {
                        Toggle("Also update the default", isOn: $updateDefault)
                    } footer: {
                        Text("Off: only this period changes. On: new periods use this amount too.")
                    }
                }

                if cost != nil {
                    Section {
                        Button("Remove from this period", role: .destructive) {
                            if let cost {
                                context.delete(cost)
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(cost == nil ? "New fixed cost" : "Fixed cost")
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
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cost {
            cost.name = trimmed
            cost.amount = amount
            cost.isSavings = isSavings
            cost.category = category
            if updateDefault, let template = linkedMonthlyTemplate {
                template.name = trimmed
                template.amount = amount
                template.isSavings = isSavings
                template.category = category
            }
        } else {
            let order = (period.fixedCosts ?? []).map(\.sortOrder).max() ?? 0
            let newCost = PeriodFixedCost(name: trimmed, amount: amount, isSavings: isSavings,
                                          sortOrder: order + 1, templateKey: "", detail: "This period only")
            context.insert(newCost)
            newCost.period = period
            newCost.category = category
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - New-period check-in

struct CheckInView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @Query private var expenses: [Expense]
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @State private var movedToGoalName: String?

    let period: BudgetPeriod
    @State private var incomeTarget: IncomeEditTarget?
    @State private var costTarget: FixedCostEditTarget?

    private var previousLeftover: Double {
        guard let previous = PeriodManager.previous(of: period, in: periods) else { return 0 }
        return PeriodManager.leftToSpend(in: previous, expenses: expenses)
    }

    private var hasAddedLeftover: Bool {
        (period.incomes ?? []).contains { $0.sourceKey == PeriodManager.leftoverSourceKey }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("It's payday!")
                            .font(.title2.bold())
                        Text(AppFormat.periodTitle(start: period.startDate, lastDay: period.lastDay))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Check your income and fixed costs for this period. Tap an item to change it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                PeriodIncomeSections(period: period, showsExtra: false) { incomeTarget = $0 }

                if previousLeftover > 0 && !hasAddedLeftover && movedToGoalName == nil {
                    Section {
                        Button {
                            addLeftover()
                        } label: {
                            Label("Add \(previousLeftover.asCurrency) left over from last period",
                                  systemImage: "arrow.uturn.down.circle")
                        }
                        if !goals.isEmpty {
                            Menu {
                                ForEach(goals) { goal in
                                    Button(goal.name) {
                                        goal.savedAmount += previousLeftover
                                        try? context.save()
                                        movedToGoalName = goal.name
                                    }
                                }
                            } label: {
                                Label("Put \(previousLeftover.asCurrency) in a savings goal", systemImage: "star")
                            }
                        }
                    } footer: {
                        Text("Optional: use what you didn't spend last period in this one, or save it.")
                    }
                }

                if let movedToGoalName {
                    Section {
                        Label("\(previousLeftover.asCurrency) added to \(movedToGoalName)", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }

                PeriodFixedCostSections(period: period) { costTarget = $0 }

                Section {
                    AmountRow(title: "Left to spend this period",
                              amount: period.totalIncome - period.totalFixedCosts)
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("New period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start period") {
                        period.isCheckedIn = true
                        try? context.save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $incomeTarget) { target in
                IncomeEntryEditView(period: period, target: target)
            }
            .sheet(item: $costTarget) { target in
                PeriodFixedCostEditView(period: period, target: target)
            }
        }
    }

    private func addLeftover() {
        let entry = IncomeEntry(name: "Left over from last period", amount: previousLeftover, isExtra: false,
                                date: period.startDate, sortOrder: 1000,
                                sourceKey: PeriodManager.leftoverSourceKey)
        context.insert(entry)
        entry.period = period
        try? context.save()
    }
}
