import SwiftUI
import SwiftData

// MARK: - Drafts (kept in memory until the wizard is finished)

struct DraftIncome: Identifiable {
    let id = UUID()
    var name: String
    var amountText: String = ""

    var amount: Double { amountText.parsedNonNegativeAmount ?? 0 }
}

struct DraftFixedCost: Identifiable {
    let id = UUID()
    var name: String
    var amountText: String = ""
    var frequency: CostFrequency = .monthly
    var mode: ChargeMode = .whenDue
    var anchorDate: Date = .now
    var isSavings: Bool = false

    var amount: Double { amountText.parsedNonNegativeAmount ?? 0 }

    var spec: FixedCostSpec {
        FixedCostSpec(amount: amount, frequency: frequency, mode: mode, anchorDate: anchorDate)
    }
}

struct DraftCategory: Identifiable {
    let id = UUID()
    var name: String
    var icon: String
    var colorName: String
    var budgetText: String
    var carryOver: Bool = false

    var budget: Double { budgetText.parsedNonNegativeAmount ?? 0 }
}

// MARK: - Wizard

struct SetupWizardView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(RootView.setupKey) private var didCompleteSetup = false
    @Query private var bankConnections: [BankConnection]

    private enum Step: Int, CaseIterable {
        case welcome, payday, bank, income, fixedCosts, budgets, summary

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .payday: return "Pay day"
            case .bank: return "Your bank"
            case .income: return "Net income"
            case .fixedCosts: return "Fixed costs"
            case .budgets: return "Budgets"
            case .summary: return "Summary"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var rule = PaydayRule.standard
    @State private var incomes: [DraftIncome] = [DraftIncome(name: "Salary")]
    @State private var fixedCosts: [DraftFixedCost] = []
    @State private var categories: [DraftCategory] = Suggestions.categories.map {
        DraftCategory(name: $0.name, icon: $0.icon, colorName: $0.color, budgetText: $0.budget.editableAmount)
    }
    @State private var editingCostID: UUID?
    @State private var showingOverBudgetAlert = false
    @State private var showingBankImport = false

    private var hasBankConnection: Bool {
        bankConnections.contains { $0.isValid }
    }

    // MARK: Totals

    private var firstPeriodStart: Date { rule.periodStart(containing: .now) }
    private var firstPeriodEnd: Date { rule.nextPayday(after: firstPeriodStart) }
    private var firstPeriodLastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: firstPeriodEnd) ?? firstPeriodEnd
    }

    private var totalIncome: Double { incomes.reduce(0) { $0 + $1.amount } }

    private var totalFixed: Double {
        let start = firstPeriodStart
        let end = firstPeriodEnd
        return fixedCosts.reduce(0) { $0 + $1.spec.charge(start: start, end: end).amount }
    }

    private var totalSavings: Double {
        let start = firstPeriodStart
        let end = firstPeriodEnd
        return fixedCosts.filter(\.isSavings).reduce(0) { $0 + $1.spec.charge(start: start, end: end).amount }
    }

    private var totalBudgets: Double { categories.reduce(0) { $0 + $1.budget } }
    private var buffer: Double { totalIncome - totalFixed - totalBudgets }

    // MARK: Body

    var body: some View {
        NavigationStack {
            stepContent
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(step.title)
                .toolbar {
                    if step != .welcome {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back") { move(by: -1) }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Text("\(step.rawValue) of \(Step.allCases.count - 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    bottomButton
                }
                .sheet(isPresented: Binding(get: { editingCostID != nil },
                                            set: { if !$0 { editingCostID = nil } })) {
                    costSheet
                }
                .sheet(isPresented: $showingBankImport) {
                    NavigationStack {
                        FixedCostImportView { drafts in
                            fixedCosts.append(contentsOf: drafts)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showingBankImport = false }
                            }
                        }
                    }
                }
                .alert("More than your income", isPresented: $showingOverBudgetAlert) {
                    Button("Finish anyway") { finish() }
                    Button("Go back", role: .cancel) {}
                } message: {
                    Text("Your fixed costs and budgets are \((-buffer).asCurrency) more than your income. You can change this later in Settings.")
                }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .payday: paydayStep
        case .bank: bankStep
        case .income: incomeStep
        case .fixedCosts: fixedCostsStep
        case .budgets: budgetsStep
        case .summary: summaryStep
        }
    }

    private var bottomButton: some View {
        Button {
            if step == .summary {
                if buffer < 0 {
                    showingOverBudgetAlert = true
                } else {
                    finish()
                }
            } else {
                move(by: 1)
            }
        } label: {
            Text(bottomButtonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var bottomButtonTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .summary: return "Finish setup"
        case .bank: return hasBankConnection ? "Next" : "Skip for now"
        default: return "Next"
        }
    }

    private func move(by offset: Int) {
        if let next = Step(rawValue: step.rawValue + offset) {
            withAnimation { step = next }
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "eurosign.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)

                Text("Let's set up your budget")
                    .font(.title.bold())

                Text("This takes about two minutes. You'll set:")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    Label("When your salary arrives, so your periods run from payday to payday", systemImage: "calendar")
                    Label("Optionally your bank, to import fixed costs and transactions", systemImage: "building.columns")
                    Label("Your net income per period", systemImage: "arrow.down.circle")
                    Label("Your fixed costs and savings", systemImage: "house")
                    Label("Budgets for your day-to-day spending", systemImage: "chart.pie")
                }

                Text("You can change everything later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paydayStep: some View {
        Form {
            Section {
                Picker("Salary arrives on day", selection: $rule.day) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
            } footer: {
                Text("Each period starts on this day of the month. In shorter months the last day of the month is used.")
            }

            Section {
                Picker("If it's a Saturday", selection: $rule.saturday) {
                    ForEach(WeekendShift.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker("If it's a Sunday", selection: $rule.sunday) {
                    ForEach(WeekendShift.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            } header: {
                Text("Weekends")
            } footer: {
                Text("When payday falls on a weekend, the period starts on the day your salary actually arrives.")
            }

            Section {
                LabeledContent("Current period",
                               value: AppFormat.periodTitle(start: firstPeriodStart, lastDay: firstPeriodLastDay))
                LabeledContent("Next payday", value: firstPeriodEnd.shortDayTitle)
            } header: {
                Text("Preview")
            }
        }
    }

    private var bankStep: some View {
        Form {
            Section {
                Text("Connect ABN AMRO, Revolut or another bank to import your fixed costs and transactions instead of typing them in. This is optional: you can skip it and do it later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            BankSetupSections()
        }
    }

    private var incomeStep: some View {
        Form {
            Section {
                ForEach($incomes) { $income in
                    HStack {
                        TextField("Name", text: $income.name)
                        AmountField(placeholder: "0.00", text: $income.amountText)
                            .frame(maxWidth: 140)
                    }
                }
                .onDelete { offsets in
                    incomes.remove(atOffsets: offsets)
                }

                Button {
                    incomes.append(DraftIncome(name: ""))
                } label: {
                    Label("Add income", systemImage: "plus")
                }
            } header: {
                Text("Net income per period")
            } footer: {
                Text("What comes in every period, after tax. You can adjust the amounts on each payday, and add extra income (refunds, Tikkies) during a period.")
            }

            let remaining = Suggestions.incomeNames.filter { name in
                !incomes.contains { $0.name == name }
            }
            if !remaining.isEmpty {
                Section {
                    ForEach(remaining, id: \.self) { name in
                        Button {
                            incomes.append(DraftIncome(name: name))
                        } label: {
                            Label(name, systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Suggestions")
                }
            }

            Section {
                AmountRow(title: "Total income", amount: totalIncome)
                    .fontWeight(.semibold)
            }
        }
    }

    private var fixedCostsStep: some View {
        Form {
            if hasBankConnection {
                Section {
                    Button {
                        showingBankImport = true
                    } label: {
                        Label("Import from your bank", systemImage: "building.columns")
                    }
                } footer: {
                    Text("Finds recurring payments in the last six months. You choose which ones to add.")
                }
            }

            Section {
                if fixedCosts.isEmpty {
                    Text("No fixed costs yet. Pick some from the suggestions below, or add your own.")
                        .foregroundStyle(.secondary)
                }
                ForEach($fixedCosts) { $cost in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $cost.name)
                            AmountField(placeholder: "0.00", text: $cost.amountText)
                                .frame(maxWidth: 140)
                        }
                        Button {
                            editingCostID = cost.id
                        } label: {
                            HStack(spacing: 4) {
                                Text(cost.frequency.title)
                                if cost.frequency != .monthly {
                                    Text("· \(cost.mode.title.lowercased())")
                                }
                                if cost.isSavings {
                                    Text("· savings")
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    fixedCosts.remove(atOffsets: offsets)
                }

                Button {
                    let cost = DraftFixedCost(name: "")
                    fixedCosts.append(cost)
                    editingCostID = cost.id
                } label: {
                    Label("Add your own", systemImage: "plus")
                }
            } header: {
                Text("Your fixed costs")
            } footer: {
                Text("Fixed costs are taken off your income at the start of every period. Tap \"Monthly\" to change how often a cost is charged, or to mark it as savings.")
            }

            let remaining = Suggestions.fixedCostNames.filter { name in
                !fixedCosts.contains { $0.name == name }
            }
            if !remaining.isEmpty {
                Section {
                    ForEach(remaining, id: \.self) { name in
                        Button {
                            fixedCosts.append(DraftFixedCost(name: name, isSavings: name == "Savings"))
                        } label: {
                            Label(name, systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Suggestions")
                }
            }

            Section {
                AmountRow(title: "Fixed costs this period", amount: totalFixed)
                    .fontWeight(.semibold)
            }
        }
    }

    private var budgetsStep: some View {
        Form {
            Section {
                AmountRow(title: "Income minus fixed costs", amount: totalIncome - totalFixed)
                AmountRow(title: "Assigned to budgets", amount: totalBudgets)
                AmountRow(title: buffer >= 0 ? "Not assigned" : "Over-assigned",
                          amount: abs(buffer),
                          color: buffer >= 0 ? .primary : .red)
                    .fontWeight(.semibold)
            }

            Section {
                ForEach($categories) { $category in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            CategoryIcon(icon: category.icon,
                                         color: CategoryPalette.color(named: category.colorName),
                                         size: 30)
                            TextField("Name", text: $category.name)
                            AmountField(placeholder: "0.00", text: $category.budgetText)
                                .frame(maxWidth: 120)
                        }
                        Toggle("Carry over what's left", isOn: $category.carryOver)
                            .font(.subheadline)
                    }
                }
                .onDelete { offsets in
                    categories.remove(atOffsets: offsets)
                }

                Button {
                    categories.append(DraftCategory(name: "", icon: "tag", colorName: "teal", budgetText: ""))
                } label: {
                    Label("Add category", systemImage: "plus")
                }
            } header: {
                Text("Budgets per period")
            } footer: {
                Text("Carry over: what's left in a category (or what you overspent) moves to the next period. You can change icons and colors later in Settings.")
            }

            if buffer < 0 {
                Section {
                    Label("Your fixed costs and budgets are \((-buffer).asCurrency) more than your income.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var summaryStep: some View {
        Form {
            Section {
                AmountRow(title: "Net income", amount: totalIncome, sign: "+ ")
                AmountRow(title: "Fixed costs",
                          subtitle: totalSavings > 0 ? "incl. \(totalSavings.asCurrency) savings" : nil,
                          amount: totalFixed, sign: "− ")
                AmountRow(title: "Budgets", amount: totalBudgets, sign: "− ")
                AmountRow(title: "Buffer", amount: buffer,
                          color: buffer < 0 ? .red : .green)
                    .fontWeight(.semibold)
            } header: {
                Text("First period: \(AppFormat.periodTitle(start: firstPeriodStart, lastDay: firstPeriodLastDay))")
            }

            if buffer < 0 {
                Section {
                    Label("Your fixed costs and budgets are \((-buffer).asCurrency) more than your income.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } footer: {
                    Text("You can still finish, and adjust your budgets later in Settings.")
                }
            }

            Section {
                Text("From now on the app follows your pay periods. On every payday you get a short check-in to confirm your income and fixed costs for the new period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Fixed cost options sheet

    @ViewBuilder
    private var costSheet: some View {
        if let id = editingCostID, let index = fixedCosts.firstIndex(where: { $0.id == id }) {
            NavigationStack {
                Form {
                    FixedCostFields(name: $fixedCosts[index].name,
                                    amountText: $fixedCosts[index].amountText,
                                    frequency: $fixedCosts[index].frequency,
                                    mode: $fixedCosts[index].mode,
                                    anchorDate: $fixedCosts[index].anchorDate,
                                    isSavings: $fixedCosts[index].isSavings)
                }
                .navigationTitle("Fixed cost")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { editingCostID = nil }
                    }
                }
            }
        }
    }

    // MARK: Finish

    private func finish() {
        PeriodManager.resetAllData(context: context)
        rule.save()

        var order = 0
        for income in incomes {
            let name = income.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            context.insert(IncomeSource(name: name, amount: income.amount, sortOrder: order))
            order += 1
        }

        order = 0
        for cost in fixedCosts {
            let name = cost.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, cost.amount > 0 else { continue }
            context.insert(FixedCostTemplate(name: name, amount: cost.amount, frequency: cost.frequency,
                                             mode: cost.mode, anchorDate: cost.anchorDate,
                                             isSavings: cost.isSavings, sortOrder: order))
            order += 1
        }

        order = 0
        for category in categories {
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            context.insert(BudgetCategory(name: name, icon: category.icon, colorName: category.colorName,
                                          budget: category.budget, carryOver: category.carryOver,
                                          sortOrder: order))
            order += 1
        }
        try? context.save()

        let start = rule.periodStart(containing: .now)
        PeriodManager.createPeriod(start: start, end: rule.nextPayday(after: start), checkedIn: true, context: context)
        try? context.save()

        didCompleteSetup = true
    }
}
