import SwiftUI
import SwiftData
import Charts

// MARK: - Trends per category

struct TrendsView: View {
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query private var expenses: [Expense]

    /// Empty = all variable spending.
    @State private var categoryID: String = ""

    private struct Point: Identifiable {
        let id: Date
        let label: String
        let amount: Double
        let isCurrent: Bool
    }

    private var selectedCategory: BudgetCategory? {
        categories.first { "\($0.persistentModelID.hashValue)" == categoryID }
    }

    private var points: [Point] {
        periods.suffix(8).map { period in
            let amount: Double
            if let category = selectedCategory {
                amount = PeriodManager.spent(in: period, category: category, expenses: expenses)
            } else {
                amount = PeriodManager.spent(in: period, expenses: expenses)
            }
            return Point(id: period.startDate,
                         label: period.startDate.formatted(.dateTime.day().month(.abbreviated)),
                         amount: amount,
                         isCurrent: period.isCurrent)
        }
    }

    var body: some View {
        let points = self.points
        let finished = points.filter { !$0.isCurrent }
        let average = finished.isEmpty ? 0 : finished.reduce(0) { $0 + $1.amount } / Double(finished.count)
        let insights: [String] = {
            guard let current = periods.last(where: { $0.isCurrent }) ?? periods.last else { return [] }
            return Insights.categoryInsights(current: current, periods: periods, expenses: expenses,
                                             categories: categories)
        }()

        List {
            if !insights.isEmpty {
                Section {
                    ForEach(insights, id: \.self) { text in
                        Label(text, systemImage: "lightbulb")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Stands out")
                }
            }

            Section {
                Picker("Category", selection: $categoryID) {
                    Text("All variable spending").tag("")
                    ForEach(categories) { category in
                        Text(category.name).tag("\(category.persistentModelID.hashValue)")
                    }
                }

                if points.isEmpty {
                    Text("No periods yet.").foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(points) { point in
                            BarMark(x: .value("Period", point.label),
                                    y: .value("Spent", point.amount),
                                    width: .ratio(0.6))
                                .foregroundStyle(Color("ChartVariable").opacity(point.isCurrent ? 0.5 : 1))
                                .cornerRadius(4)
                        }
                        if average > 0 {
                            RuleMark(y: .value("Average", average))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .foregroundStyle(Color.secondary)
                                .annotation(position: .top, alignment: .leading) {
                                    Text("avg \(average.asCurrency)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 220)
                    .padding(.vertical, 8)
                }
            } footer: {
                Text("Variable spending per period (your expenses, not fixed costs). The current period is shown lighter because it isn't finished.")
            }

            Section {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.label + (point.isCurrent ? " (now)" : ""))
                        Spacer()
                        Text(point.amount.asCurrency)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Per period")
            }
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Fixed cost check and yearly overview

struct FixedCostCheckView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query private var connections: [BankConnection]

    @State private var changes: [FixedCostChange] = []
    @State private var newPayments: [RecurringSuggestion] = []
    @State private var isChecking = false
    @State private var hasChecked = false
    @State private var errorMessage: String?

    private var hasBank: Bool { connections.contains { $0.isValid } }

    var body: some View {
        let sorted = templates.sorted { FixedCostMonitor.yearlyAmount($0) > FixedCostMonitor.yearlyAmount($1) }
        let yearlyTotal = templates.reduce(0) { $0 + FixedCostMonitor.yearlyAmount($1) }

        List {
            if hasBank {
                Section {
                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Label(hasChecked ? "Check again" : "Check with my bank", systemImage: "arrow.triangle.2.circlepath")
                            if isChecking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isChecking)

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    if hasChecked && changes.isEmpty && newPayments.isEmpty && errorMessage == nil {
                        Label("Everything matches your bank.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }

                    ForEach(changes) { change in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.template.name)
                                Text("\(change.template.amount.asCurrency) → \(change.newAmount.asCurrency)")
                                    .font(.caption)
                                    .foregroundStyle(change.newAmount > change.template.amount ? Color.orange : Color.green)
                            }
                            Spacer()
                            Button("Update") {
                                update(change)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    ForEach(newPayments) { suggestion in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                Text("New · \(suggestion.frequency.title.lowercased()) · \(suggestion.amount.asCurrency)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Add") {
                                add(suggestion)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Changes")
                } footer: {
                    Text("Compares the last six months at your bank with your fixed costs: price changes and new recurring payments. This also runs once a week by itself if notifications for fixed cost changes are on.")
                }
            }

            Section {
                ForEach(sorted) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text("\(template.amount.asCurrency) \(template.frequency.perLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(FixedCostMonitor.yearlyAmount(template).asCurrency)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Per year")
            } footer: {
                Text("Total \(yearlyTotal.asCurrency) a year, about \((yearlyTotal / 12).asCurrency) a month.")
            }
        }
        .navigationTitle("Fixed costs check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func check() async {
        isChecking = true
        errorMessage = nil
        defer {
            isChecking = false
            hasChecked = true
        }
        do {
            let result = try await FixedCostMonitor.check(context: context)
            changes = result.changes
            newPayments = result.newPayments
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ change: FixedCostChange) {
        change.template.amount = change.newAmount
        if let current = periods.last(where: { $0.isCurrent }), change.template.frequency == .monthly {
            for cost in current.fixedCosts ?? [] where cost.templateKey == change.template.key {
                cost.amount = change.newAmount
            }
        }
        try? context.save()
        changes.removeAll { $0.id == change.id }
    }

    private func add(_ suggestion: RecurringSuggestion) {
        let order = (templates.map(\.sortOrder).max() ?? -1) + 1
        let template = FixedCostTemplate(name: suggestion.name, amount: suggestion.amount,
                                         frequency: suggestion.frequency, mode: .whenDue,
                                         anchorDate: suggestion.lastDate, isSavings: false, sortOrder: order)
        context.insert(template)
        template.category = AutoCategory.suggest(for: suggestion.name, in: categories)
        try? context.save()
        if let current = periods.last(where: { $0.isCurrent }) {
            PeriodManager.addMissingDefaultFixedCosts(to: current, context: context)
        }
        newPayments.removeAll { $0.id == suggestion.id }
    }
}

// MARK: - Bank balance check

struct BalanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankConnection.createdAt) private var connections: [BankConnection]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @Query private var expenses: [Expense]

    private struct AccountBalance: Identifiable {
        let id: String
        let name: String
        let amount: Double?
        let currency: String
    }

    @State private var balances: [AccountBalance] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        let total = balances.compactMap(\.amount).reduce(0, +)
        let current = periods.last { $0.isCurrent }
        let left = current.map { PeriodManager.leftToSpend(in: $0, expenses: expenses) }

        List {
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading balances…").foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(balances) { balance in
                    HStack {
                        Text(balance.name)
                        Spacer()
                        Text(balance.amount.map { $0.asCurrency } ?? "Not available")
                            .monospacedDigit()
                            .foregroundStyle(balance.amount == nil ? Color.secondary : Color.primary)
                    }
                }
                if balances.count > 1 {
                    AmountRow(title: "Total", amount: total)
                        .fontWeight(.semibold)
                }
            } header: {
                Text("At your bank")
            }

            if let left, !balances.isEmpty {
                Section {
                    AmountRow(title: "Left to spend in Budget", amount: left)
                    AmountRow(title: "Bank balance minus left to spend", amount: total - left)
                } footer: {
                    Text("The difference is roughly what's reserved for fixed costs that haven't been charged yet, your savings, and money you didn't put in Budget. If it's much lower than you expect, an expense may be missing.")
                }
            }
        }
        .navigationTitle("Balance check")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = try EnableBankingClient.fromSettings()
            var result: [AccountBalance] = []
            for connection in connections where connection.isValid {
                for account in connection.accounts ?? [] where account.isEnabled {
                    let money = try? await client.balance(accountUID: account.uid)
                    result.append(AccountBalance(id: account.uid,
                                                 name: "\(connection.bankName) · \(account.displayName)",
                                                 amount: money?.amount,
                                                 currency: money?.currency ?? account.currency))
                }
            }
            balances = result
            if result.isEmpty {
                errorMessage = BankError.noConnections.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
