import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @Query(sort: \IncomeSource.sortOrder) private var incomeSources: [IncomeSource]
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]

    @AppStorage(PaydayRule.dayKey) private var paydayDay = PaydayRule.standard.day
    @AppStorage(PaydayRule.saturdayKey) private var saturdayRaw = PaydayRule.standard.saturday.rawValue
    @AppStorage(PaydayRule.sundayKey) private var sundayRaw = PaydayRule.standard.sunday.rawValue
    @AppStorage(RootView.setupKey) private var didCompleteSetup = true

    @State private var confirmingReset = false

    private var rule: PaydayRule {
        PaydayRule(day: paydayDay,
                   saturday: WeekendShift(rawValue: saturdayRaw) ?? PaydayRule.standard.saturday,
                   sunday: WeekendShift(rawValue: sundayRaw) ?? PaydayRule.standard.sunday)
    }

    private var currentPeriod: BudgetPeriod? {
        periods.last { $0.isCurrent }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                paydaySection

                Section {
                    NavigationLink {
                        IncomeSourcesView()
                    } label: {
                        LabeledContent("Income",
                                       value: incomeSources.reduce(0) { $0 + $1.amount }.asCurrency)
                    }
                    NavigationLink {
                        FixedCostTemplatesView()
                    } label: {
                        LabeledContent("Fixed costs & savings",
                                       value: "≈ " + templates.reduce(0) { $0 + $1.spec.averagePerPeriod }.asCurrency)
                    }
                    NavigationLink {
                        CategoriesSettingsView()
                    } label: {
                        LabeledContent("Categories & budgets",
                                       value: categories.reduce(0) { $0 + $1.budget }.asCurrency)
                    }
                } header: {
                    Text("Defaults for new periods")
                } footer: {
                    Text("Every new period starts with these. To change only the current period, tap Income or Fixed costs on the Overview.")
                }

                Section {
                    ShareLink(item: CSVExport(csv: makeCSV()),
                              preview: SharePreview("expenses.csv")) {
                        Label("Export expenses (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(expenses.isEmpty)

                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("Reset all data and run setup", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your data is stored only on this iPhone. Export it now and then as a backup: deleting the app deletes your data.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Expenses recorded", value: "\(expenses.count)")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: paydayDay) { _, _ in applyRule() }
            .onChange(of: saturdayRaw) { _, _ in applyRule() }
            .onChange(of: sundayRaw) { _, _ in applyRule() }
            .alert("Reset everything?", isPresented: $confirmingReset) {
                Button("Reset", role: .destructive) {
                    PeriodManager.resetAllData(context: context)
                    didCompleteSetup = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All expenses, periods, income, fixed costs and categories are deleted, and the setup wizard starts again.")
            }
        }
    }

    private var paydaySection: some View {
        Section {
            Picker("Salary arrives on day", selection: $paydayDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            Picker("If it's a Saturday", selection: $saturdayRaw) {
                ForEach(WeekendShift.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            Picker("If it's a Sunday", selection: $sundayRaw) {
                ForEach(WeekendShift.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
        } header: {
            Text("Pay day")
        } footer: {
            if let currentPeriod {
                Text("Current period: \(AppFormat.periodTitle(start: currentPeriod.startDate, lastDay: currentPeriod.lastDay)). Next payday: \(currentPeriod.endDate.shortDayTitle).")
            }
        }
    }

    private func applyRule() {
        PeriodManager.applyRuleToCurrentPeriod(context: context, rule: rule)
    }

    /// CSV export. Uses ";" when the device uses a decimal comma, so Excel/Numbers open it correctly.
    private func makeCSV() -> String {
        func field(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let separator = AppFormat.locale.decimalSeparator == "," ? ";" : ","
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var lines = [["Date", "Amount", "Category", "Note"].joined(separator: separator)]
        for expense in expenses {
            lines.append([
                expense.date.formatted(dateStyle),
                expense.amount.editableAmount,
                field(expense.category?.name ?? ""),
                field(expense.note),
            ].joined(separator: separator))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }
}

struct CSVExport: Transferable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("expenses.csv")
            try export.csv.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Categories

struct CategoriesSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @State private var pendingDelete: BudgetCategory?

    private var totalBudget: Double {
        categories.reduce(0) { $0 + $1.budget }
    }

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryEditView(category: category)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                if category.carryOver {
                                    Text("Carries over")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(category.budget > 0 ? category.budget.asCurrency : "No budget")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete { offsets in
                    if let index = offsets.first {
                        pendingDelete = categories[index]
                    }
                }

                NavigationLink {
                    CategoryEditView(category: nil)
                } label: {
                    Label("Add category", systemImage: "plus")
                }
            } footer: {
                Text("Total budget per period: \(totalBudget.asCurrency). Swipe left to delete, or tap Edit to reorder.")
            }
        }
        .navigationTitle("Categories & budgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .alert("Delete category?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { category in
            Button("Delete", role: .destructive) {
                context.delete(category)
                try? context.save()
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { category in
            Text("\"\(category.name)\" and all \(category.expenses?.count ?? 0) expenses in this category will be deleted.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
        try? context.save()
    }
}

// MARK: - Default income

struct IncomeSourcesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeSource.sortOrder) private var sources: [IncomeSource]
    @State private var editing: IncomeSource?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(sources) { source in
                    Button {
                        editing = source
                    } label: {
                        AmountRow(title: source.name, amount: source.amount)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(sources[index])
                    }
                    try? context.save()
                }

                Button {
                    adding = true
                } label: {
                    Label("Add income", systemImage: "plus")
                }
            } footer: {
                Text("Net income that comes in every period. New periods start with these amounts; you can adjust them in the payday check-in.")
            }
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { source in
            IncomeSourceEditView(source: source)
        }
        .sheet(isPresented: $adding) {
            IncomeSourceEditView(source: nil)
        }
    }
}

struct IncomeSourceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeSource.sortOrder) private var sources: [IncomeSource]

    private let source: IncomeSource?
    @State private var name: String
    @State private var amountText: String

    init(source: IncomeSource?) {
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _amountText = State(initialValue: source?.amount.editableAmountOrEmpty ?? "")
    }

    private var amount: Double? { amountText.parsedNonNegativeAmount }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Salary", text: $name)
                    AmountField(placeholder: "0.00", text: $amountText)
                } footer: {
                    Text("Net amount per period.")
                }
            }
            .navigationTitle(source == nil ? "New income" : "Income")
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
        if let source {
            source.name = trimmed
            source.amount = amount
        } else {
            let order = (sources.map(\.sortOrder).max() ?? -1) + 1
            context.insert(IncomeSource(name: trimmed, amount: amount, sortOrder: order))
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Default fixed costs

struct FixedCostTemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @State private var editing: FixedCostTemplate?
    @State private var adding = false

    var body: some View {
        let regular = templates.filter { !$0.isSavings }
        let savings = templates.filter { $0.isSavings }

        List {
            Section {
                ForEach(regular) { template in
                    row(for: template)
                }
                .onDelete { offsets in
                    for index in offsets {
                        context.delete(regular[index])
                    }
                    try? context.save()
                }

                Button {
                    adding = true
                } label: {
                    Label("Add fixed cost", systemImage: "plus")
                }
            } header: {
                Text("Fixed costs")
            } footer: {
                Text("Changes apply from the next period. To change the current period, tap Fixed costs on the Overview.")
            }

            if !savings.isEmpty {
                Section {
                    ForEach(savings) { template in
                        row(for: template)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(savings[index])
                        }
                        try? context.save()
                    }
                } header: {
                    Text("Savings")
                }
            }
        }
        .navigationTitle("Fixed costs & savings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { template in
            FixedCostTemplateEditView(template: template)
        }
        .sheet(isPresented: $adding) {
            FixedCostTemplateEditView(template: nil)
        }
    }

    private func row(for template: FixedCostTemplate) -> some View {
        Button {
            editing = template
        } label: {
            AmountRow(title: template.name,
                      subtitle: subtitle(for: template),
                      amount: template.amount)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for template: FixedCostTemplate) -> String {
        if template.frequency == .monthly {
            return "Monthly"
        }
        return "\(template.frequency.title) · \(template.mode.title.lowercased())"
    }
}

struct FixedCostTemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]

    private let template: FixedCostTemplate?
    @State private var name: String
    @State private var amountText: String
    @State private var frequency: CostFrequency
    @State private var mode: ChargeMode
    @State private var anchorDate: Date
    @State private var isSavings: Bool

    init(template: FixedCostTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _amountText = State(initialValue: template?.amount.editableAmountOrEmpty ?? "")
        _frequency = State(initialValue: template?.frequency ?? .monthly)
        _mode = State(initialValue: template?.mode ?? .whenDue)
        _anchorDate = State(initialValue: template?.anchorDate ?? .now)
        _isSavings = State(initialValue: template?.isSavings ?? false)
    }

    private var amount: Double? { amountText.parsedAmount }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                FixedCostFields(name: $name, amountText: $amountText, frequency: $frequency,
                                mode: $mode, anchorDate: $anchorDate, isSavings: $isSavings)
            }
            .navigationTitle(template == nil ? "New fixed cost" : "Fixed cost")
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
        if let template {
            template.name = trimmed
            template.amount = amount
            template.frequency = frequency
            template.mode = mode
            template.anchorDate = anchorDate
            template.isSavings = isSavings
        } else {
            let order = (templates.map(\.sortOrder).max() ?? -1) + 1
            context.insert(FixedCostTemplate(name: trimmed, amount: amount, frequency: frequency, mode: mode,
                                             anchorDate: anchorDate, isSavings: isSavings, sortOrder: order))
        }
        try? context.save()
        dismiss()
    }
}
