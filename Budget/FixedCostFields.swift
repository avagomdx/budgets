import SwiftUI

/// Form sections for editing a fixed cost. Used by the setup wizard and by Settings.
struct FixedCostFields: View {
    @Binding var name: String
    @Binding var amountText: String
    @Binding var frequency: CostFrequency
    @Binding var mode: ChargeMode
    @Binding var anchorDate: Date
    @Binding var isSavings: Bool

    private var spec: FixedCostSpec {
        FixedCostSpec(amount: amountText.parsedNonNegativeAmount ?? 0, frequency: frequency,
                      mode: mode, anchorDate: anchorDate)
    }

    var body: some View {
        Section {
            TextField("Name", text: $name)
            AmountField(placeholder: "0.00", text: $amountText)
        } footer: {
            Text("Amount \(frequency.perLabel).")
        }

        Section {
            Picker("How often", selection: $frequency) {
                ForEach(CostFrequency.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if frequency != .monthly {
                Picker("Count it", selection: $mode) {
                    ForEach(ChargeMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                DatePicker("A date it's charged", selection: $anchorDate, displayedComponents: .date)
            }
        } header: {
            Text("Frequency")
        } footer: {
            Text(frequencyExplanation)
        }

        Section {
            Toggle("This is savings", isOn: $isSavings)
        } footer: {
            Text("Savings are set aside at the start of every period, just like fixed costs, and are shown separately.")
        }
    }

    private var frequencyExplanation: String {
        switch frequency {
        case .monthly:
            return "Counted once in every period."
        case .weekly:
            return mode == .whenDue
                ? "Counted for every week it's charged in the period (4 or 5 times), based on the date above."
                : "Counted as an average of \(spec.averagePerPeriod.asCurrency) in every period."
        case .quarterly, .yearly:
            return mode == .whenDue
                ? "Only counted in the period in which it's charged, based on the date above."
                : "Set aside \(spec.averagePerPeriod.asCurrency) in every period, so the money is there when it's charged."
        }
    }
}
