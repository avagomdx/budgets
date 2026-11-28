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
    @AppStorage(Notifications.Kind.payday.rawValue) private var notifyPayday = false
    @AppStorage(Notifications.Kind.budget.rawValue) private var notifyBudget = false
    @AppStorage(Notifications.Kind.weekly.rawValue) private var notifyWeekly = false
    @AppStorage(Notifications.Kind.fixedCostChanges.rawValue) private var notifyFixedChanges = false
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var shareFile: ShareFile?
    @State private var importing = false
    @State private var pickedBackupURL: URL?
    @State private var pendingRestore: BackupFile?
    @State private var errorMessage: String?

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

                notificationsSection
                securitySection
                moreSection

                Section {
                    NavigationLink {
                        BankSettingsView()
                    } label: {
                        Label("Bank connections", systemImage: "building.columns")
                    }
                } header: {
                    Text("Bank")
                } footer: {
                    Text("Connect ABN AMRO, Revolut and other banks through Enable Banking to import fixed costs or transactions.")
                }

                Section {
                    Button {
                        share { try BackupManager.writeBackupFile(context: context) }
                    } label: {
                        Label("Back up all data", systemImage: "externaldrive.badge.plus")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Restore from backup", systemImage: "externaldrive.badge.timemachine")
                    }
                    Button {
                        share { try BackupManager.writeCSV(context: context) }
                    } label: {
                        Label("Export to CSV (Excel)", systemImage: "tablecells")
                    }

                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("Reset all data and run setup", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your data is stored only on this iPhone. Make a backup now and then, and save it in Files or iCloud Drive: deleting the app deletes your data. The CSV contains all expenses and fixed costs, with their category and period.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Expenses recorded", value: "\(expenses.count)")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: notifyPayday) { _, on in notificationsChanged(on) }
            .onChange(of: notifyBudget) { _, on in notificationsChanged(on) }
            .onChange(of: notifyWeekly) { _, on in notificationsChanged(on) }
            .onChange(of: notifyFixedChanges) { _, on in notificationsChanged(on) }
            .onChange(of: paydayDay) { _, _ in applyRule() }
            .onChange(of: saturdayRaw) { _, _ in applyRule() }
            .onChange(of: sundayRaw) { _, _ in applyRule() }
            .sheet(item: $shareFile) { file in
                ActivityView(items: [file.url])
            }
            .sheet(isPresented: $importing, onDismiss: {
                if let url = pickedBackupURL {
                    pickedBackupURL = nil
                    readBackup(from: url)
                }
            }) {
                DocumentPicker(contentTypes: [.json]) { url in
                    pickedBackupURL = url
                }
                .ignoresSafeArea()
            }
            .alert("Restore backup?",
                   isPresented: Binding(get: { pendingRestore != nil },
                                        set: { if !$0 { pendingRestore = nil } }),
                   presenting: pendingRestore) { backup in
                Button("Restore", role: .destructive) {
                    BackupManager.restore(backup, context: context)
                    pendingRestore = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRestore = nil
                }
            } message: { backup in
                Text("All current data is replaced with the backup from \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).")
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
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

    private var notificationsSection: some View {
        Section {
            Toggle("Payday reminder", isOn: $notifyPayday)
            Toggle("Budget at 80% and 100%", isOn: $notifyBudget)
            Toggle("Weekly summary (Sunday)", isOn: $notifyWeekly)
            Toggle("Fixed cost changes", isOn: $notifyFixedChanges)
        } header: {
            Text("Notifications")
        } footer: {
            Text("The weekly summary uses your numbers from the last time you opened the app.")
        }
    }

    private var securitySection: some View {
        Section {
            Toggle("Lock with Face ID", isOn: Binding(get: { lockEnabled }, set: { newValue in
                if newValue {
                    Task {
                        if await AppLock.authenticate(reason: "Turn on the app lock") {
                            lockEnabled = true
                        }
                    }
                } else {
                    lockEnabled = false
                }
            }))
        } header: {
            Text("Security")
        } footer: {
            Text("Asks for Face ID (or your passcode) when you open Budget.")
        }
    }

    private var moreSection: some View {
        Section {
            NavigationLink {
                GoalsView()
            } label: {
                Label("Savings goals", systemImage: "star")
            }
            NavigationLink {
                RulesView()
            } label: {
                Label("Category rules", systemImage: "wand.and.stars")
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
        Notifications.reschedule(context: context)
    }

    private func notificationsChanged(_ turnedOn: Bool) {
        Task {
            if turnedOn {
                _ = await Notifications.requestPermission()
            }
            Notifications.reschedule(context: context)
        }
    }

    private func share(_ makeFile: () throws -> URL) {
        do {
            shareFile = ShareFile(url: try makeFile())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readBackup(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)  // the picker gave us a temporary copy
            pendingRestore = try BackupManager.decode(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Categories

struct CategoriesSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query private var expenses: [Expense]
    @Query private var rules: [CategoryRule]
    @State private var pendingDelete: BudgetCategory?
    @State private var autoMessage: String?

    private var uncategorized: [Expense] {
        expenses.filter { $0.category == nil }
    }

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

            Section {
                Button {
                    autoCategorize()
                } label: {
                    Label("Auto-categorize \(uncategorized.count) expenses", systemImage: "wand.and.stars")
                }
                .disabled(uncategorized.isEmpty)
            } footer: {
                Text("Gives expenses without a category one based on the shop, e.g. Albert Heijn, Jumbo and Lidl → a category called Groceries or Boodschappen. Imported transactions get this automatically.")
            }
        }
        .alert("Auto-categorize",
               isPresented: Binding(get: { autoMessage != nil }, set: { if !$0 { autoMessage = nil } })) {
            Button("OK", role: .cancel) { autoMessage = nil }
        } message: {
            Text(autoMessage ?? "")
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
            Text("\"\(category.name)\" and all \(category.expenses?.count ?? 0) expenses in this category will be deleted. Fixed costs in this category keep existing, without a category.")
        }
    }

    private func autoCategorize() {
        let candidates = uncategorized
        let total = candidates.count
        var count = 0
        for expense in candidates {
            if let category = AutoCategory.suggest(for: expense.note, in: categories, rules: rules) {
                expense.category = category
                count += 1
            }
        }
        try? context.save()
        autoMessage = count == 0
            ? "No known shops found among \(total) expenses without a category."
            : "\(count) of \(total) expenses got a category. The rest weren't recognized."
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
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @State private var editing: FixedCostTemplate?
    @State private var adding = false
    @State private var resultMessage: String?

    private var currentPeriod: BudgetPeriod? {
        periods.last { $0.isCurrent }
    }

    var body: some View {
        let regular = templates.filter { !$0.isSavings }
        let savings = templates.filter { $0.isSavings }

        List {
            Section {
                NavigationLink {
                    AssignCategoriesView()
                } label: {
                    Label("Assign categories", systemImage: "tag")
                }
                NavigationLink {
                    FixedCostCheckView()
                } label: {
                    Label("Check with bank & yearly overview", systemImage: "checklist")
                }
            } footer: {
                Text("Give each fixed cost a category, to see fixed and variable costs per category.")
            }

            if let currentPeriod {
                Section {
                    Button {
                        let added = PeriodManager.addMissingDefaultFixedCosts(to: currentPeriod, context: context)
                        resultMessage = added == 0
                            ? "All your default fixed costs are already in the current period."
                            : "Added \(added) fixed \(added == 1 ? "cost" : "costs") to the current period."
                    } label: {
                        Label("Add to current period", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Adds the defaults that aren't in \(AppFormat.periodTitle(start: currentPeriod.startDate, lastDay: currentPeriod.lastDay)) yet. Fixed costs already in that period stay as they are.")
                }
            }

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
        .alert("Current period",
               isPresented: Binding(get: { resultMessage != nil },
                                    set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
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
        var parts: [String] = [template.frequency.title]
        if template.frequency != .monthly {
            parts.append(template.mode.title.lowercased())
        }
        parts.append(template.category?.name ?? "no category")
        return parts.joined(separator: " · ")
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
    @State private var category: BudgetCategory?

    init(template: FixedCostTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _amountText = State(initialValue: template?.amount.editableAmountOrEmpty ?? "")
        _frequency = State(initialValue: template?.frequency ?? .monthly)
        _mode = State(initialValue: template?.mode ?? .whenDue)
        _anchorDate = State(initialValue: template?.anchorDate ?? .now)
        _isSavings = State(initialValue: template?.isSavings ?? false)
        _category = State(initialValue: template?.category)
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
                Section {
                    CategoryPickerRow(selection: $category)
                } footer: {
                    Text("Used to show fixed and variable costs per category. Applied to all periods.")
                }
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
            template.category = category
            PeriodManager.syncCategory(of: template, context: context)
        } else {
            let order = (templates.map(\.sortOrder).max() ?? -1) + 1
            let newTemplate = FixedCostTemplate(name: trimmed, amount: amount, frequency: frequency, mode: mode,
                                                anchorDate: anchorDate, isSavings: isSavings, sortOrder: order)
            context.insert(newTemplate)
            newTemplate.category = category
        }
        try? context.save()
        dismiss()
    }
}
