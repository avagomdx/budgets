import SwiftUI
import SwiftData

struct ExpensesView: View {
    @Binding var showingAdd: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var month = Date.now
    @State private var editing: Expense?
    @State private var searchText = ""

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Expense]
        var id: Date { day }
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    private var groups: [DayGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = expenses.filter { expense in
            guard expense.date.isSameMonth(as: month) else { return false }
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
        searchText.isEmpty ? "Geen uitgaven" : "Niets gevonden"
    }

    private var emptyMessage: String {
        searchText.isEmpty
            ? "Er zijn nog geen uitgaven in \(month.monthTitle.lowercased())."
            : "Probeer een andere zoekterm."
    }

    var body: some View {
        let groups = self.groups

        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $month)
                }

                if groups.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(emptyMessage)
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(groups) { group in
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
                            Text(group.total.euro).monospacedDigit()
                        }
                        .textCase(nil)
                    }
                }
            }
            .navigationTitle("Uitgaven")
            .searchable(text: $searchText, prompt: "Zoek op notitie of categorie")
            .sheet(item: $editing) { expense in
                ExpenseFormView(expense: expense)
            }
            .safeAreaInset(edge: .bottom) {
                AddExpenseButton { showingAdd = true }
            }
        }
    }
}
