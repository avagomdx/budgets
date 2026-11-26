import Foundation
import SwiftData
import SwiftUI

@Model
final class BudgetCategory {
    var name: String = ""
    var icon: String = "tag"
    var colorName: String = "blue"
    /// Monthly budget. 0 = no budget.
    var monthlyBudget: Double = 0
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Expense.category)
    var expenses: [Expense]? = []

    init(name: String, icon: String, colorName: String, monthlyBudget: Double, sortOrder: Int) {
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.monthlyBudget = monthlyBudget
        self.sortOrder = sortOrder
    }

    var color: Color { CategoryPalette.color(named: colorName) }
}

@Model
final class Expense {
    var amount: Double = 0
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now
    var category: BudgetCategory?

    init(amount: Double, date: Date, note: String, category: BudgetCategory?) {
        self.amount = amount
        self.date = date
        self.note = note
        self.category = category
        self.createdAt = .now
    }
}

// MARK: - Colors and icons

struct PaletteColor: Identifiable {
    let name: String
    let color: Color
    var id: String { name }
}

enum CategoryPalette {
    static let colors: [PaletteColor] = [
        PaletteColor(name: "green", color: .green),
        PaletteColor(name: "mint", color: .mint),
        PaletteColor(name: "teal", color: .teal),
        PaletteColor(name: "blue", color: .blue),
        PaletteColor(name: "indigo", color: .indigo),
        PaletteColor(name: "purple", color: .purple),
        PaletteColor(name: "pink", color: .pink),
        PaletteColor(name: "red", color: .red),
        PaletteColor(name: "orange", color: .orange),
        PaletteColor(name: "yellow", color: .yellow),
        PaletteColor(name: "brown", color: .brown),
        PaletteColor(name: "gray", color: .gray),
    ]

    static let icons: [String] = [
        "cart", "fork.knife", "cup.and.saucer", "car", "fuelpump", "tram",
        "house", "bolt", "phone", "tshirt", "bag", "gift",
        "gamecontroller", "film", "book", "airplane", "figure.run", "heart",
        "cross.case", "pawprint", "graduationcap", "wrench.and.screwdriver", "creditcard", "ellipsis.circle",
    ]

    static func color(named name: String) -> Color {
        colors.first { $0.name == name }?.color ?? .gray
    }
}

// MARK: - Default categories on first launch

enum DefaultData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<BudgetCategory>())) ?? 0
        guard count == 0 else { return }

        let defaults: [(name: String, icon: String, color: String, budget: Double)] = [
            ("Groceries", "cart", "green", 400),
            ("Dining out", "fork.knife", "orange", 150),
            ("Transport", "car", "blue", 150),
            ("Leisure", "gamecontroller", "purple", 100),
            ("Clothing", "tshirt", "pink", 75),
            ("Other", "ellipsis.circle", "gray", 100),
        ]
        for (index, item) in defaults.enumerated() {
            context.insert(BudgetCategory(name: item.name, icon: item.icon, colorName: item.color,
                                          monthlyBudget: item.budget, sortOrder: index))
        }
        try? context.save()
    }
}
