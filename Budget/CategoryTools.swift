import SwiftUI
import SwiftData
import Charts
import UIKit

// MARK: - Category picker

/// "Category" picker with a "None" option.
struct CategoryPickerRow: View {
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Binding var selection: BudgetCategory?

    var body: some View {
        Picker("Category", selection: $selection) {
            Text("None").tag(nil as BudgetCategory?)
            ForEach(categories) { category in
                Label(category.name, systemImage: category.icon)
                    .tag(Optional(category))
            }
        }
    }
}

// MARK: - Creating a category from just a name

@MainActor
enum CategoryFactory {
    /// Creates a category with a matching icon and an unused color. No budget.
    static func make(name: String, context: ModelContext) -> BudgetCategory {
        let existing = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let usedColors = Set(existing.map(\.colorName))
        let color = CategoryPalette.colors.first { !usedColors.contains($0.name) }?.name ?? "teal"
        let order = (existing.map(\.sortOrder).max() ?? -1) + 1
        let category = BudgetCategory(name: name, icon: icon(for: name), colorName: color,
                                      budget: 0, carryOver: false, sortOrder: order)
        context.insert(category)
        try? context.save()
        return category
    }

    static func icon(for name: String) -> String {
        let lower = name.lowercased()
        let rules: [(keywords: [String], icon: String)] = [
            (["hous", "rent", "mortgage", "home", "wonen", "huur", "hypotheek"], "house"),
            (["insur", "verzeker"], "shield"),
            (["subscr", "stream", "abonnement", "netflix", "spotify"], "repeat"),
            (["saving", "spaar"], "banknote"),
            (["tax", "belasting"], "building.columns"),
            (["energy", "utilit", "energie", "gas", "water"], "bolt"),
            (["car", "auto", "transport", "fuel"], "car"),
            (["phone", "internet", "telefoon", "mobile"], "phone"),
            (["health", "zorg", "doctor", "pharma"], "cross.case"),
            (["gym", "sport", "fitness"], "figure.run"),
            (["child", "kid", "kind", "school"], "graduationcap"),
            (["pet", "dog", "cat", "hond", "kat"], "pawprint"),
        ]
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            return rule.icon
        }
        return "tag"
    }
}

// MARK: - Assign categories to fixed costs

struct AssignCategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]

    @State private var newCategoryFor: FixedCostTemplate?
    @State private var newCategoryName = ""

    var body: some View {
        List {
            Section {
                if templates.isEmpty {
                    Text("You don't have any fixed costs yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text("\(template.amount.asCurrency) · \(template.frequency.title.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        menu(for: template)
                    }
                }
            } footer: {
                Text("The category is applied to every period, including earlier ones, so the breakdown by category is complete. Use \"New category…\" for things like Housing, Insurance or Subscriptions.")
            }
        }
        .navigationTitle("Assign categories")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New category",
               isPresented: Binding(get: { newCategoryFor != nil },
                                    set: { if !$0 { newCategoryFor = nil } })) {
            TextField("e.g. Housing", text: $newCategoryName)
            Button("Add") { addCategory() }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        } message: {
            Text("It's created without a budget. You can set one later in Settings.")
        }
    }

    private func menu(for template: FixedCostTemplate) -> some View {
        Menu {
            Button {
                assign(nil, to: template)
            } label: {
                Text("None")
            }
            ForEach(categories) { category in
                Button {
                    assign(category, to: template)
                } label: {
                    Label(category.name, systemImage: category.icon)
                }
            }
            Divider()
            Button {
                newCategoryName = ""
                newCategoryFor = template
            } label: {
                Label("New category…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                if let category = template.category {
                    CategoryIcon(category: category, size: 22)
                    Text(category.name)
                        .foregroundStyle(.primary)
                } else {
                    Text("Choose")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
        }
    }

    private func assign(_ category: BudgetCategory?, to template: FixedCostTemplate) {
        template.category = category
        PeriodManager.syncCategory(of: template, context: context)
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let template = newCategoryFor else { return }
        let category = CategoryFactory.make(name: name, context: context)
        assign(category, to: template)
        newCategoryName = ""
        newCategoryFor = nil
    }
}

// MARK: - Variable vs fixed per category

struct BreakdownRow: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let variable: Double
    let fixed: Double

    var total: Double { variable + fixed }
}

struct CategoryBreakdownView: View {
    let period: BudgetPeriod

    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query private var expenses: [Expense]

    private var rows: [BreakdownRow] {
        var result: [BreakdownRow] = categories.map { category in
            BreakdownRow(id: "\(category.persistentModelID.hashValue)",
                         name: category.name,
                         icon: category.icon,
                         color: category.color,
                         variable: PeriodManager.spent(in: period, category: category, expenses: expenses),
                         fixed: PeriodManager.fixedCosts(in: period, category: category))
        }

        let unassigned = (period.fixedCosts ?? []).filter { $0.category == nil }
        let unassignedFixed = unassigned.filter { !$0.isSavings }.reduce(0) { $0 + $1.amount }
        let unassignedSavings = unassigned.filter(\.isSavings).reduce(0) { $0 + $1.amount }
        if unassignedFixed > 0 {
            result.append(BreakdownRow(id: "no-category", name: "No category", icon: "questionmark",
                                       color: .gray, variable: 0, fixed: unassignedFixed))
        }
        if unassignedSavings > 0 {
            result.append(BreakdownRow(id: "savings", name: "Savings", icon: "banknote",
                                       color: .gray, variable: 0, fixed: unassignedSavings))
        }
        return result
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    private var unassignedCount: Int {
        (period.fixedCosts ?? []).filter { $0.category == nil }.count
    }

    private var unassignedText: String {
        unassignedCount == 1
            ? "1 fixed cost has no category"
            : "\(unassignedCount) fixed costs have no category"
    }

    var body: some View {
        let rows = self.rows
        let totalVariable = rows.reduce(0) { $0 + $1.variable }
        let totalFixed = rows.reduce(0) { $0 + $1.fixed }

        List {
            if rows.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "chart.bar",
                                       description: Text("There are no expenses or fixed costs in this period."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    BreakdownChart(rows: rows)
                        .padding(.vertical, 8)
                } header: {
                    Text(AppFormat.periodTitle(start: period.startDate, lastDay: period.lastDay))
                }

                Section {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            CategoryIcon(icon: row.icon, color: row.color, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                Text("Variable \(row.variable.asCurrency) · Fixed \(row.fixed.asCurrency)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Text(row.total.asCurrency)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Per category")
                }

                Section {
                    AmountRow(title: "Variable (your expenses)", amount: totalVariable)
                    AmountRow(title: "Fixed costs & savings", amount: totalFixed)
                    AmountRow(title: "Total", amount: totalVariable + totalFixed)
                        .fontWeight(.semibold)
                }
            }

            if unassignedCount > 0 {
                Section {
                    NavigationLink {
                        AssignCategoriesView()
                    } label: {
                        Label(unassignedText, systemImage: "tag")
                    }
                }
            }
        }
        .navigationTitle("By category")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Horizontal stacked bars: variable and fixed per category.
private struct BreakdownChart: View {
    let rows: [BreakdownRow]

    var body: some View {
        Chart {
            ForEach(rows) { row in
                BarMark(x: .value("Amount", row.variable),
                        y: .value("Category", row.name),
                        height: .fixed(16))
                    .foregroundStyle(by: .value("Type", "Variable"))
                    .cornerRadius(4)
                BarMark(x: .value("Amount", row.fixed),
                        y: .value("Category", row.name),
                        height: .fixed(16))
                    .foregroundStyle(by: .value("Type", "Fixed"))
                    .cornerRadius(4)
            }
        }
        .chartForegroundStyleScale([
            "Variable": Color("ChartVariable"),
            "Fixed": Color("ChartFixed"),
        ])
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: CGFloat(rows.count) * 32 + 60)
    }
}

// MARK: - Share sheet

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
