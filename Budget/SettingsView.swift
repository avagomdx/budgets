import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @State private var pendingDelete: BudgetCategory?

    private var totalBudget: Double {
        categories.reduce(0) { $0 + $1.monthlyBudget }
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
                Section {
                    ForEach(categories) { category in
                        NavigationLink {
                            CategoryEditView(category: category)
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: category)
                                Text(category.name)
                                Spacer()
                                Text(category.monthlyBudget > 0 ? category.monthlyBudget.asCurrency : "No budget")
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
                } header: {
                    Text("Categories and budgets")
                } footer: {
                    Text("Total monthly budget: \(totalBudget.asCurrency). Swipe left to delete, or tap Edit to reorder.")
                }

                Section {
                    ShareLink(item: CSVExport(csv: makeCSV()),
                              preview: SharePreview("expenses.csv")) {
                        Label("Export expenses (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(expenses.isEmpty)
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
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
        try? context.save()
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
