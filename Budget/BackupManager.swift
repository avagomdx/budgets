import Foundation
import SwiftData

// MARK: - Backup file format (JSON)

struct BackupFile: Codable {
    var version: Int
    var createdAt: Date
    var payday: PaydayBackup
    var categories: [CategoryBackup]
    var incomeSources: [IncomeSourceBackup]
    var fixedCostTemplates: [FixedCostTemplateBackup]
    var periods: [PeriodBackup]
    var expenses: [ExpenseBackup]
}

struct PaydayBackup: Codable {
    var day: Int
    var saturday: String
    var sunday: String
}

struct CategoryBackup: Codable {
    var id: String
    var name: String
    var icon: String
    var colorName: String
    var budget: Double
    var carryOver: Bool
    var sortOrder: Int
}

struct IncomeSourceBackup: Codable {
    var key: String
    var name: String
    var amount: Double
    var sortOrder: Int
}

struct FixedCostTemplateBackup: Codable {
    var key: String
    var name: String
    var amount: Double
    var frequency: String
    var mode: String
    var anchorDate: Date
    var isSavings: Bool
    var sortOrder: Int
    var categoryID: String?
}

struct PeriodBackup: Codable {
    var startDate: Date
    var endDate: Date
    var isCheckedIn: Bool
    var incomes: [IncomeEntryBackup]
    var fixedCosts: [PeriodFixedCostBackup]
}

struct IncomeEntryBackup: Codable {
    var name: String
    var amount: Double
    var isExtra: Bool
    var date: Date
    var sortOrder: Int
    var sourceKey: String
}

struct PeriodFixedCostBackup: Codable {
    var name: String
    var amount: Double
    var isSavings: Bool
    var sortOrder: Int
    var templateKey: String
    var detail: String
    var categoryID: String?
}

struct ExpenseBackup: Codable {
    var amount: Double
    var date: Date
    var note: String
    var createdAt: Date
    var categoryID: String?
    var externalID: String?
    var source: String?
}

enum BackupError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable: return "This file isn't a Budget backup, or it's damaged."
        }
    }
}

// MARK: - Backup, restore and CSV export

@MainActor
enum BackupManager {
    static func makeBackup(context: ModelContext) -> BackupFile {
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        var ids: [PersistentIdentifier: String] = [:]
        for category in categories {
            ids[category.persistentModelID] = UUID().uuidString
        }
        func categoryID(of category: BudgetCategory?) -> String? {
            guard let category else { return nil }
            return ids[category.persistentModelID]
        }

        let sources = (try? context.fetch(FetchDescriptor<IncomeSource>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let templates = (try? context.fetch(FetchDescriptor<FixedCostTemplate>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let periods = (try? context.fetch(FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let rule = PaydayRule.saved

        var categoryItems: [CategoryBackup] = []
        for category in categories {
            categoryItems.append(CategoryBackup(id: ids[category.persistentModelID] ?? UUID().uuidString,
                                                name: category.name, icon: category.icon,
                                                colorName: category.colorName, budget: category.budget,
                                                carryOver: category.carryOver, sortOrder: category.sortOrder))
        }

        var sourceItems: [IncomeSourceBackup] = []
        for source in sources {
            sourceItems.append(IncomeSourceBackup(key: source.key, name: source.name,
                                                  amount: source.amount, sortOrder: source.sortOrder))
        }

        var templateItems: [FixedCostTemplateBackup] = []
        for template in templates {
            templateItems.append(FixedCostTemplateBackup(key: template.key, name: template.name,
                                                         amount: template.amount,
                                                         frequency: template.frequencyRaw, mode: template.modeRaw,
                                                         anchorDate: template.anchorDate,
                                                         isSavings: template.isSavings,
                                                         sortOrder: template.sortOrder,
                                                         categoryID: categoryID(of: template.category)))
        }

        var periodItems: [PeriodBackup] = []
        for period in periods {
            var incomeItems: [IncomeEntryBackup] = []
            for income in period.incomes ?? [] {
                incomeItems.append(IncomeEntryBackup(name: income.name, amount: income.amount,
                                                     isExtra: income.isExtra, date: income.date,
                                                     sortOrder: income.sortOrder, sourceKey: income.sourceKey))
            }
            var fixedItems: [PeriodFixedCostBackup] = []
            for cost in period.fixedCosts ?? [] {
                fixedItems.append(PeriodFixedCostBackup(name: cost.name, amount: cost.amount,
                                                        isSavings: cost.isSavings, sortOrder: cost.sortOrder,
                                                        templateKey: cost.templateKey, detail: cost.detail,
                                                        categoryID: categoryID(of: cost.category)))
            }
            periodItems.append(PeriodBackup(startDate: period.startDate, endDate: period.endDate,
                                            isCheckedIn: period.isCheckedIn,
                                            incomes: incomeItems, fixedCosts: fixedItems))
        }

        var expenseItems: [ExpenseBackup] = []
        for expense in expenses {
            expenseItems.append(ExpenseBackup(amount: expense.amount, date: expense.date, note: expense.note,
                                              createdAt: expense.createdAt,
                                              categoryID: categoryID(of: expense.category),
                                              externalID: expense.externalID, source: expense.source))
        }

        let payday = PaydayBackup(day: rule.day, saturday: rule.saturday.rawValue, sunday: rule.sunday.rawValue)
        return BackupFile(version: 1, createdAt: .now, payday: payday,
                          categories: categoryItems, incomeSources: sourceItems,
                          fixedCostTemplates: templateItems, periods: periodItems, expenses: expenseItems)
    }

    /// Writes a backup to a temporary file and returns its URL (for the share sheet).
    static func writeBackupFile(context: ModelContext) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(makeBackup(context: context))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Budget backup \(todayStamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    /// Replaces all data with the backup.
    static func restore(_ backup: BackupFile, context: ModelContext) {
        PeriodManager.resetAllData(context: context)

        PaydayRule(day: backup.payday.day,
                   saturday: WeekendShift(rawValue: backup.payday.saturday) ?? PaydayRule.standard.saturday,
                   sunday: WeekendShift(rawValue: backup.payday.sunday) ?? PaydayRule.standard.sunday)
            .save()

        var categories: [String: BudgetCategory] = [:]
        for item in backup.categories {
            let category = BudgetCategory(name: item.name, icon: item.icon, colorName: item.colorName,
                                          budget: item.budget, carryOver: item.carryOver, sortOrder: item.sortOrder)
            context.insert(category)
            categories[item.id] = category
        }
        func categoryFor(_ id: String?) -> BudgetCategory? {
            guard let id else { return nil }
            return categories[id]
        }

        for item in backup.incomeSources {
            let source = IncomeSource(name: item.name, amount: item.amount, sortOrder: item.sortOrder)
            source.key = item.key
            context.insert(source)
        }

        for item in backup.fixedCostTemplates {
            let template = FixedCostTemplate(name: item.name, amount: item.amount,
                                             frequency: CostFrequency(rawValue: item.frequency) ?? .monthly,
                                             mode: ChargeMode(rawValue: item.mode) ?? .whenDue,
                                             anchorDate: item.anchorDate, isSavings: item.isSavings,
                                             sortOrder: item.sortOrder)
            template.key = item.key
            context.insert(template)
            template.category = categoryFor(item.categoryID)
        }

        for item in backup.periods {
            let period = BudgetPeriod(startDate: item.startDate, endDate: item.endDate, isCheckedIn: item.isCheckedIn)
            context.insert(period)
            for income in item.incomes {
                let entry = IncomeEntry(name: income.name, amount: income.amount, isExtra: income.isExtra,
                                        date: income.date, sortOrder: income.sortOrder, sourceKey: income.sourceKey)
                context.insert(entry)
                entry.period = period
            }
            for fixed in item.fixedCosts {
                let cost = PeriodFixedCost(name: fixed.name, amount: fixed.amount, isSavings: fixed.isSavings,
                                           sortOrder: fixed.sortOrder, templateKey: fixed.templateKey,
                                           detail: fixed.detail)
                context.insert(cost)
                cost.period = period
                cost.category = categoryFor(fixed.categoryID)
            }
        }

        for item in backup.expenses {
            let expense = Expense(amount: item.amount, date: item.date, note: item.note,
                                  category: nil)
            expense.createdAt = item.createdAt
            expense.externalID = item.externalID ?? ""
            expense.source = item.source ?? ""
            context.insert(expense)
            expense.category = categoryFor(item.categoryID)
        }

        try? context.save()
        PeriodManager.ensureCurrentPeriod(context: context)
    }

    /// Expenses and fixed costs as CSV. Uses ";" when the device uses a decimal comma,
    /// so Excel/Numbers open it correctly.
    static func writeCSV(context: ModelContext) throws -> URL {
        func field(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let separator = AppFormat.locale.decimalSeparator == "," ? ";" : ","
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

        let periods = (try? context.fetch(FetchDescriptor<BudgetPeriod>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))) ?? []

        func periodTitle(for date: Date) -> String {
            guard let period = periods.first(where: { $0.contains(date) }) else { return "" }
            return AppFormat.periodTitle(start: period.startDate, lastDay: period.lastDay)
        }

        var rows: [(date: Date, line: String)] = []
        for expense in expenses {
            let line = [
                expense.date.formatted(dateStyle),
                "Variable",
                expense.amount.editableAmount,
                field(expense.category?.name ?? ""),
                field(expense.note),
                field(periodTitle(for: expense.date)),
            ].joined(separator: separator)
            rows.append((expense.date, line))
        }
        for period in periods {
            let title = AppFormat.periodTitle(start: period.startDate, lastDay: period.lastDay)
            for cost in period.sortedFixedCosts {
                let line = [
                    period.startDate.formatted(dateStyle),
                    cost.isSavings ? "Savings" : "Fixed",
                    cost.amount.editableAmount,
                    field(cost.category?.name ?? ""),
                    field(cost.name),
                    field(title),
                ].joined(separator: separator)
                rows.append((period.startDate, line))
            }
        }
        rows.sort { $0.date < $1.date }

        let header = ["Date", "Type", "Amount", "Category", "Description", "Period"].joined(separator: separator)
        let csv = "\u{FEFF}" + ([header] + rows.map { $0.line }).joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Budget expenses \(todayStamp).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static var todayStamp: String {
        Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}
