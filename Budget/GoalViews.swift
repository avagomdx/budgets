import SwiftUI
import SwiftData
import UIKit

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @State private var adding = false
    @State private var editing: SavingsGoal?

    var body: some View {
        List {
            if goals.isEmpty {
                ContentUnavailableView("No savings goals", systemImage: "star",
                                       description: Text("Save towards something, like a holiday or a new bike."))
                    .listRowBackground(Color.clear)
            }
            ForEach(goals) { goal in
                Button {
                    editing = goal
                } label: {
                    GoalRow(goal: goal, progress: GoalMath.progress(of: goal, periods: periods))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(goals[index])
                }
                try? context.save()
            }

            Section {
                Button {
                    adding = true
                } label: {
                    Label("New savings goal", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Savings goals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            GoalEditView(goal: nil)
        }
        .sheet(item: $editing) { goal in
            GoalEditView(goal: goal)
        }
    }
}

struct GoalRow: View {
    let goal: SavingsGoal
    let progress: Double

    private var fraction: Double {
        goal.targetAmount > 0 ? min(max(progress / goal.targetAmount, 0), 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(goal.name, systemImage: goal.icon)
                    .font(.headline)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .tint(fraction >= 1 ? .green : .accentColor)
            HStack {
                Text("\(progress.asCurrency) of \(goal.targetAmount.asCurrency)")
                Spacer()
                if let needed = GoalMath.neededPerPeriod(for: goal, progress: progress), needed > 0 {
                    Text("\(needed.asCurrency) per month needed")
                } else if let deadline = goal.deadline {
                    Text(deadline.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

struct GoalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]

    private let goal: SavingsGoal?
    @State private var name: String
    @State private var targetText: String
    @State private var savedText: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var linkedKey: String
    @State private var icon: String
    @State private var addText = ""

    private static let icons = ["star", "airplane", "car", "house", "gift", "bicycle", "laptopcomputer",
                                "graduationcap", "heart", "pawprint", "beach.umbrella", "banknote"]

    init(goal: SavingsGoal?) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _targetText = State(initialValue: goal?.targetAmount.editableAmountOrEmpty ?? "")
        _savedText = State(initialValue: goal?.savedAmount.editableAmountOrEmpty ?? "")
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline
            ?? Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now)
        _linkedKey = State(initialValue: goal?.linkedSavingsKey ?? "")
        _icon = State(initialValue: goal?.icon ?? "star")
    }

    private var savingsTemplates: [FixedCostTemplate] {
        templates.filter(\.isSavings)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && targetText.parsedAmount != nil
            && savedText.parsedNonNegativeAmount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Holiday", text: $name)
                    HStack {
                        Text("Target")
                        Spacer()
                        AmountField(placeholder: "0.00", text: $targetText)
                            .frame(maxWidth: 160)
                    }
                    HStack {
                        Text("Already saved")
                        Spacer()
                        AmountField(placeholder: "0.00", text: $savedText)
                            .frame(maxWidth: 160)
                    }
                }

                if goal != nil {
                    Section {
                        HStack {
                            AmountField(placeholder: "Amount", text: $addText)
                            Button("Add") {
                                if let amount = addText.parsedAmount {
                                    let current = savedText.parsedNonNegativeAmount ?? 0
                                    savedText = (current + amount).editableAmount
                                    addText = ""
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(addText.parsedAmount == nil)
                        }
                    } header: {
                        Text("Put money aside")
                    } footer: {
                        Text("Adds to \"Already saved\". Tap Save to keep it.")
                    }
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Date", selection: $deadline, in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    Text("With a deadline the app shows how much you need to save per month.")
                }

                Section {
                    Picker("Savings fixed cost", selection: $linkedKey) {
                        Text("None").tag("")
                        ForEach(savingsTemplates) { template in
                            Text("\(template.name) (\(template.amount.asCurrency))").tag(template.key)
                        }
                    }
                } footer: {
                    Text(savingsTemplates.isEmpty
                         ? "Mark a fixed cost as savings to count it towards this goal automatically."
                         : "Every period, this savings amount counts towards the goal automatically.")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(symbol == icon ? Color.white : Color.primary)
                                    .background(symbol == icon ? Color.accentColor : Color(uiColor: .secondarySystemFill),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Icon")
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Savings goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let target = targetText.parsedAmount else { return }
        let saved = savedText.parsedNonNegativeAmount ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let goal {
            goal.name = trimmed
            goal.targetAmount = target
            goal.savedAmount = saved
            goal.deadline = hasDeadline ? deadline : nil
            goal.linkedSavingsKey = linkedKey
            goal.icon = icon
        } else {
            let newGoal = SavingsGoal(name: trimmed, targetAmount: target, deadline: hasDeadline ? deadline : nil,
                                      savedAmount: saved, linkedSavingsKey: linkedKey)
            newGoal.icon = icon
            context.insert(newGoal)
        }
        try? context.save()
        dismiss()
    }
}
