import SwiftUI
import SwiftData

struct ExpensesView: View {
    @Binding var showingAdd: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @State private var selectedPeriodID: PersistentIdentifier?
    @State private var editing: Expense?
    @State private var searchText = ""
    @State private var showingImport = false
    @Query private var bankConnections: [BankConnection]
    @Query(filter: #Predicate<Expense> { $0.needsReview == true }) private var toReview: [Expense]

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Expense]
        var id: Date { day }
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    private func groups(for period: BudgetPeriod?) -> [DayGroup] {
        guard let period else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = expenses.filter { expense in
            guard period.contains(expense.date) else { return false }
            guard !query.isEmpty else { return true }
            return expense.note.localizedCaseInsensitiveContains(query)
                || (expense.category?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        return grouped
            .map { DayGroup(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private var emptyTitle: String {
        searchText.isEmpty ? "No expenses" : "No results"
    }

    private var emptyMessage: String {
        searchText.isEmpty
            ? "There are no expenses in this period yet."
            : "Try a different search term."
    }

    var body: some View {
        let period = PeriodManager.resolve(selectedPeriodID, in: periods)
        let dayGroups = groups(for: period)

        NavigationStack {
            List {
                Section {
                    PeriodSwitcher(periods: periods, selectedID: $selectedPeriodID)
                }

                if !toReview.isEmpty {
                    Section {
                        ReviewBanner(count: toReview.count)
                    }
                }

                if dayGroups.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(emptyMessage)
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.items) { expense in
                            Button {
                                editing = expense
                            } label: {
                                ExpenseRow(expense: expense)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                context.delete(group.items[index])
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.day.dayTitle)
                            Spacer()
                            Text(group.total.asCurrency).monospacedDigit()
                        }
                        .textCase(nil)
                    }
                }
            }
            .navigationTitle("Expenses")
            .refreshable {
                await BankSync.syncIfNeeded(context: context, force: true)
            }
            .toolbar {
                if bankConnections.contains(where: { $0.isValid }) {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import from bank", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showingImport) {
                TransactionImportView()
            }
            .searchable(text: $searchText, prompt: "Search notes or categories")
            .sheet(item: $editing) { expense in
                ExpenseFormView(expense: expense)
            }
            .safeAreaInset(edge: .bottom) {
                AddExpenseButton { showingAdd = true }
            }
        }
    }
}
