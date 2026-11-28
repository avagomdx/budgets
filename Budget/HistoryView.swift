import SwiftUI
import SwiftData

/// One block per period: income, fixed costs, spent, left over and saved.
struct HistoryView: View {
    @Query(sort: \BudgetPeriod.startDate, order: .reverse) private var periods: [BudgetPeriod]
    @Query private var expenses: [Expense]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TrendsView()
                    } label: {
                        Label("Trends per category", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        GoalsView()
                    } label: {
                        Label("Savings goals", systemImage: "star")
                    }
                }

                if periods.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock",
                                           description: Text("Your pay periods will show up here."))
                        .listRowBackground(Color.clear)
                }

                ForEach(periods) { period in
                    let spent = PeriodManager.spent(in: period, expenses: expenses)
                    let left = period.totalIncome - period.totalFixedCosts - spent
                    let saved = period.totalSavings + left

                    Section {
                        AmountRow(title: "Income", amount: period.totalIncome, sign: "+ ")
                        AmountRow(title: "Fixed costs",
                                  subtitle: period.totalSavings > 0
                                      ? "incl. \(period.totalSavings.asCurrency) savings" : nil,
                                  amount: period.totalFixedCosts, sign: "− ")
                        AmountRow(title: "Spent", amount: spent, sign: "− ")
                        AmountRow(title: period.isCurrent ? "Left so far" : "Left over",
                                  amount: left,
                                  color: left < 0 ? .red : .primary)
                            .fontWeight(.semibold)
                        if !period.isCurrent {
                            AmountRow(title: "Saved",
                                      subtitle: "Savings plus what was left over",
                                      amount: saved,
                                      color: saved < 0 ? .red : .green)
                        }
                    } header: {
                        HStack {
                            Text(AppFormat.periodTitle(start: period.startDate, lastDay: period.lastDay))
                            Spacer()
                            if period.isCurrent {
                                Text("Current")
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}
