import SwiftUI
import SwiftData

struct OverviewView: View {
    @Binding var showingAdd: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @Query private var bankConnections: [BankConnection]
    @AppStorage("bankPromptDismissed") private var bankPromptDismissed = false
    @State private var selectedPeriodID: PersistentIdentifier?
    @State private var confirmingEarlyStart = false
    @State private var showingBankSetup = false
    @State private var showingFixedImport = false
    @State private var showingTransactionImport = false

    private var hasBankConnection: Bool {
        bankConnections.contains { $0.isValid }
    }

    var body: some View {
        let period = PeriodManager.resolve(selectedPeriodID, in: periods)

        NavigationStack {
            List {
                Section {
                    PeriodSwitcher(periods: periods, selectedID: $selectedPeriodID)
                }

                if bankConnections.isEmpty && !bankPromptDismissed {
                    bankPrompt
                }

                if let period {
                    content(for: period)
                } else {
                    Text("No period yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            confirmingEarlyStart = true
                        } label: {
                            Label("Salary came early", systemImage: "forward.end")
                        }
                        .disabled(!canStartEarly)

                        Section {
                            if hasBankConnection {
                                Button {
                                    showingTransactionImport = true
                                } label: {
                                    Label("Import transactions from bank", systemImage: "square.and.arrow.down")
                                }
                                Button {
                                    showingFixedImport = true
                                } label: {
                                    Label("Import fixed costs from bank", systemImage: "repeat")
                                }
                            }
                            Button {
                                showingBankSetup = true
                            } label: {
                                Label("Bank connections", systemImage: "building.columns")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add expense")
                }
            }
            .confirmationDialog("Start the next period today?", isPresented: $confirmingEarlyStart,
                                titleVisibility: .visible) {
                Button("Start new period today") { startEarly() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current period ends yesterday, and a new period starts today with a check-in. Expenses from today onwards count for the new period.")
            }
            .navigationDestination(isPresented: $showingBankSetup) {
                BankSettingsView()
            }
            .navigationDestination(isPresented: $showingFixedImport) {
                FixedCostImportView()
            }
            .navigationDestination(isPresented: $showingTransactionImport) {
                TransactionImportView()
            }
            .safeAreaInset(edge: .bottom) {
                AddExpenseButton { showingAdd = true }
            }
        }
    }

    private var bankPrompt: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Connect your bank", systemImage: "building.columns")
                    .font(.headline)
                Text("Import your fixed costs and transactions from ABN AMRO, Revolut and other banks, instead of typing them in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Set up") {
                        showingBankSetup = true
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not now") {
                        bankPromptDismissed = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for period: BudgetPeriod) -> some View {
        let periodExpenses = PeriodManager.expenses(in: period, from: expenses)
        let spent = periodExpenses.reduce(0) { $0 + $1.amount }

        Section {
            LeftToSpendCard(period: period, spent: spent)
        }

        Section {
            NavigationLink {
                PeriodIncomeView(period: period)
            } label: {
                AmountRow(title: "Income", amount: period.totalIncome, sign: "+ ")
            }
            NavigationLink {
                PeriodFixedCostsView(period: period)
            } label: {
                AmountRow(title: "Fixed costs",
                          subtitle: period.totalSavings > 0 ? "incl. \(period.totalSavings.asCurrency) savings" : nil,
                          amount: period.totalFixedCosts, sign: "− ")
            }
            AmountRow(title: "Spent", amount: spent, sign: "− ")
        }

        Section {
            NavigationLink {
                CategoryBreakdownView(period: period)
            } label: {
                Label("Variable vs fixed by category", systemImage: "chart.bar.xaxis")
            }

            ForEach(categories) { category in
                let categorySpent = PeriodManager.spent(in: period, category: category, expenses: expenses)
                let carried = PeriodManager.carriedIn(category: category, period: period,
                                                      periods: periods, expenses: expenses)
                let fixed = PeriodManager.fixedCosts(in: period, category: category)
                NavigationLink {
                    CategoryDetailView(category: category, period: period)
                } label: {
                    BudgetRow(category: category, spent: categorySpent, carried: carried, fixed: fixed)
                }
            }
        } header: {
            Text("Budgets")
        }

        if !periodExpenses.isEmpty {
            Section {
                ForEach(periodExpenses.prefix(5)) { expense in
                    ExpenseRow(expense: expense, showDate: true)
                }
            } header: {
                Text("Recent expenses")
            }
        }
    }

    // MARK: - Salary came early

    private var currentPeriod: BudgetPeriod? {
        periods.last { $0.isCurrent }
    }

    private var canStartEarly: Bool {
        guard let current = currentPeriod else { return false }
        return !Calendar.current.isDateInToday(current.startDate)
    }

    private func startEarly() {
        guard let current = currentPeriod else { return }
        PeriodManager.startNextPeriodEarly(current: current, context: context)
        selectedPeriodID = nil
    }
}

// MARK: - Left to spend

private struct LeftToSpendCard: View {
    let period: BudgetPeriod
    let spent: Double

    private var left: Double { period.totalIncome - period.totalFixedCosts - spent }

    private var title: String {
        period.endDate <= .now ? "Left over" : "Left to spend"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(left.asCurrency)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(left < 0 ? Color.red : Color.primary)
                .contentTransition(.numericText())

            if period.isCurrent {
                let days = PeriodManager.daysLeft(in: period)
                let dayWord = days == 1 ? "day" : "days"
                if left > 0 {
                    Label("About \((left / Double(days)).asCurrency) per day for \(days) \(dayWord)",
                          systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Label("Next payday: \(period.endDate.shortDayTitle)", systemImage: "banknote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .animation(.default, value: left)
    }
}

private struct BudgetRow: View {
    let category: BudgetCategory
    let spent: Double
    let carried: Double
    let fixed: Double

    private var budget: Double { category.budget + carried }

    private var fixedNote: String {
        "Fixed \(fixed.asCurrency) · Total \((spent + fixed).asCurrency)"
    }

    private var carryNote: String {
        carried > 0
            ? "incl. \(carried.asCurrency) carried over"
            : "\((-carried).asCurrency) overspent last period"
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.name)
                    Spacer()
                    Text(spent.asCurrency)
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(budget > 0 && spent > budget ? Color.red : Color.primary)
                }
                BudgetBar(spent: spent, budget: budget, color: category.color)
                if carried != 0 {
                    Text(carryNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if fixed > 0 {
                    Text(fixedNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
