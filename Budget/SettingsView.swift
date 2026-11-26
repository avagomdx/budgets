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
                                Text(category.monthlyBudget > 0 ? category.monthlyBudget.euro : "Geen budget")
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
                        Label("Categorie toevoegen", systemImage: "plus")
                    }
                } header: {
                    Text("Categorieën en budgetten")
                } footer: {
                    Text("Totaal budget per maand: \(totalBudget.euro). Veeg naar links om te verwijderen, of tik op Wijzig om de volgorde aan te passen.")
                }

                Section {
                    ShareLink(item: CSVExport(csv: makeCSV()),
                              preview: SharePreview("uitgaven.csv")) {
                        Label("Exporteer uitgaven (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(expenses.isEmpty)
                } header: {
                    Text("Gegevens")
                } footer: {
                    Text("Je gegevens staan alleen op deze iPhone. Exporteer af en toe als back-up, want als je de app verwijdert ben je ze kwijt.")
                }

                Section {
                    LabeledContent("Versie", value: appVersion)
                    LabeledContent("Aantal uitgaven", value: "\(expenses.count)")
                }
            }
            .navigationTitle("Instellingen")
            .toolbar {
                EditButton()
            }
            .alert("Categorie verwijderen?",
                   isPresented: Binding(get: { pendingDelete != nil },
                                        set: { if !$0 { pendingDelete = nil } }),
                   presenting: pendingDelete) { category in
                Button("Verwijder", role: .destructive) {
                    context.delete(category)
                    try? context.save()
                    pendingDelete = nil
                }
                Button("Annuleer", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { category in
                Text("\"\(category.name)\" en alle \(category.expenses?.count ?? 0) uitgaven in deze categorie worden verwijderd.")
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

    /// CSV met puntkomma's en komma-decimalen, zodat Nederlandse Excel/Numbers het direct goed opent.
    private func makeCSV() -> String {
        func field(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var lines = ["Datum;Bedrag;Categorie;Notitie"]
        for expense in expenses {
            lines.append([
                expense.date.formatted(dateStyle),
                expense.amount.editableAmount,
                field(expense.category?.name ?? ""),
                field(expense.note),
            ].joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }
}

struct CSVExport: Transferable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitgaven.csv")
            try export.csv.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
