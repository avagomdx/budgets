import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - Bank setup (used in Settings and in the setup wizard)

/// "Enable Banking app" and "Banks" sections. Put inside a List or Form.
struct BankSetupSections: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankConnection.createdAt) private var connections: [BankConnection]

    @AppStorage(BankSettings.appIDKey) private var appID = ""
    @AppStorage(BankSettings.redirectURLKey) private var redirectURL = ""

    @State private var hasKey = BankSettings.hasPrivateKey
    @State private var importingKey = false
    @State private var pickedKeyURL: URL?
    @State private var message: String?

    private var isReady: Bool {
        !appID.trimmingCharacters(in: .whitespaces).isEmpty && hasKey
    }

    var body: some View {
        Section {
            Link(destination: URL(string: "https://enablebanking.com")!) {
                Label("Open Enable Banking", systemImage: "safari")
            }

            Button {
                importingKey = true
            } label: {
                HStack {
                    Label(hasKey ? "Private key imported" : "Import private key (.pem)", systemImage: "key")
                    Spacer()
                    if hasKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            TextField("Application ID", text: $appID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))

            TextField(BankSettings.defaultRedirectURL, text: $redirectURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.footnote)
        } header: {
            Text("Step 1 · Enable Banking app")
        } footer: {
            Text("Register a free Production app at Enable Banking and link your own accounts there. Then import the .pem file it gives you; the application ID is filled in from the file name. The key stays in this iPhone's keychain. Leave the redirect URL empty to use the default.")
        }
        .sheet(isPresented: $importingKey, onDismiss: {
            if let url = pickedKeyURL {
                pickedKeyURL = nil
                importKey(from: url)
            }
        }) {
            DocumentPicker(contentTypes: [.item]) { url in
                pickedKeyURL = url
            }
            .ignoresSafeArea()
        }
        .alert("Bank connections",
               isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }

        Section {
            ForEach(connections) { connection in
                connectionRow(connection)
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(connections[index])
                }
                try? context.save()
            }

            NavigationLink {
                BankPickerView()
            } label: {
                Label(connections.isEmpty ? "Connect a bank" : "Connect another bank", systemImage: "plus")
            }
            .disabled(!isReady)
        } header: {
            Text("Step 2 · Your banks")
        } footer: {
            Text(isReady
                 ? "Your bank's login opens in Safari and sends you back here. Access lasts 90–180 days; after that, connect the bank again."
                 : "Finish step 1 first.")
        }
    }

    private func connectionRow(_ connection: BankConnection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(connection.bankName).font(.headline)
                Spacer()
                if connection.isValid {
                    Text("Until \(connection.validUntil.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Expired, reconnect")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            ForEach(connection.accounts ?? []) { account in
                Text(account.iban.isEmpty ? account.displayName : "\(account.displayName) · \(account.iban)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importKey(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)  // the picker gave us a temporary copy
            guard let pem = String(data: data, encoding: .utf8) else {
                throw BankError.invalidKey("the file isn't text.")
            }
            _ = try PrivateKeyLoader.secKey(fromPEM: pem)  // check it's usable before saving
            try Keychain.save(Data(pem.utf8), account: BankSettings.keychainAccount)
            hasKey = true

            // Enable Banking names the file after the application ID.
            let fileName = url.deletingPathExtension().lastPathComponent
            var text = "Private key imported."
            if UUID(uuidString: fileName) != nil {
                appID = fileName
                text += " The application ID was filled in from the file name."
            }
            message = text + " You can delete the .pem file from Files now."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Settings → Bank connections

struct BankSettingsView: View {
    @Query private var connections: [BankConnection]

    private var hasValidConnection: Bool {
        connections.contains { $0.isValid }
    }

    var body: some View {
        List {
            BankSetupSections()

            Section {
                NavigationLink {
                    FixedCostImportView()
                } label: {
                    Label("Import fixed costs", systemImage: "repeat")
                }
                NavigationLink {
                    TransactionImportView()
                } label: {
                    Label("Import transactions", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("Step 3 · Import")
            } footer: {
                Text("Fixed costs: finds recurring payments in the last six months. Transactions: adds your payments as expenses after you've reviewed them. You can also start both from the ⋯ menu on the Overview.")
            }
            .disabled(!hasValidConnection)
        }
        .navigationTitle("Bank connections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Choose a bank

struct BankPickerView: View {
    @Environment(\.openURL) private var openURL

    private struct Country: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    private static let countries: [Country] = [
        Country(code: "NL", name: "Netherlands"), Country(code: "BE", name: "Belgium"),
        Country(code: "DE", name: "Germany"), Country(code: "LT", name: "Lithuania"),
        Country(code: "FR", name: "France"), Country(code: "ES", name: "Spain"),
        Country(code: "IE", name: "Ireland"), Country(code: "GB", name: "United Kingdom"),
    ]

    @State private var country = "NL"
    @State private var banks: [ASPSP] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var connectingID: String?
    @State private var message: String?

    private var filteredBanks: [ASPSP] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return banks }
        return banks.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                Picker("Country", selection: $country) {
                    ForEach(Self.countries) { item in
                        Text(item.name).tag(item.code)
                    }
                }
            } footer: {
                Text("Revolut may be listed under Lithuania (LT) if you don't find it under your own country.")
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading banks…").foregroundStyle(.secondary)
                    }
                }
                ForEach(filteredBanks) { bank in
                    Button {
                        connect(bank)
                    } label: {
                        HStack {
                            Text(bank.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if connectingID == bank.id {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(connectingID != nil)
                }
            } footer: {
                Text("Your bank's login opens in Safari. After you approve access, you're sent back to Budget.")
            }
        }
        .navigationTitle("Connect a bank")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search banks")
        .task(id: country) {
            await loadBanks()
        }
        .alert("Couldn't connect",
               isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func loadBanks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let client = try EnableBankingClient.fromSettings()
            banks = try await client.banks(country: country)
        } catch {
            banks = []
            message = error.localizedDescription
        }
    }

    private func connect(_ bank: ASPSP) {
        connectingID = bank.id
        Task {
            do {
                let url = try await BankLink.start(bank: bank)
                openURL(url)
            } catch {
                message = error.localizedDescription
            }
            connectingID = nil
        }
    }
}

// MARK: - Small category menu for import rows

struct CategoryMenu: View {
    let categories: [BudgetCategory]
    @Binding var selection: BudgetCategory?

    var body: some View {
        Menu {
            Button("None") { selection = nil }
            ForEach(categories) { category in
                Button {
                    selection = category
                } label: {
                    Label(category.name, systemImage: category.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let selection {
                    CategoryIcon(category: selection, size: 20)
                    Text(selection.name)
                        .lineLimit(1)
                } else {
                    Text("Category")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
        }
    }
}

// MARK: - Import: fixed costs

struct FixedCostImportRow: Identifiable {
    let id: String
    var include: Bool
    var name: String
    var amountText: String
    var frequency: CostFrequency
    var category: BudgetCategory?
    var isSavings: Bool
    var anchorDate: Date
    let info: String
    let warning: Bool
    let alreadyExists: Bool

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amountText.parsedAmount != nil
    }
}

struct FixedCostImportView: View {
    /// Set by the setup wizard: selected items are handed back as drafts instead of being saved.
    var onAddDrafts: (([DraftFixedCost]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]

    @State private var rows: [FixedCostImportRow] = []
    @State private var merchants: [MerchantSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var addToCurrentPeriod = true
    @State private var resultMessage: String?
    @State private var showingMerchants = false

    private var isWizard: Bool { onAddDrafts != nil }

    private var selectedCount: Int {
        rows.filter { $0.include && $0.isValid }.count
    }

    private var addButtonTitle: String {
        selectedCount == 1 ? "Add 1 fixed cost" : "Add \(selectedCount) fixed costs"
    }

    var body: some View {
        let newIndices = rows.indices.filter { !rows[$0].alreadyExists }
        let existingIndices = rows.indices.filter { rows[$0].alreadyExists }
        let allNewSelected = newIndices.allSatisfy { rows[$0].include }

        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Looking for recurring payments…").foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                Section {
                    Text("Tick the payments you want as fixed costs. Tap a name or amount to change it, and pick how often it's charged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if newIndices.isEmpty {
                        Text("No new recurring payments found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(newIndices, id: \.self) { index in
                        FixedCostImportRowView(row: $rows[index], categories: categories, showsCategory: !isWizard)
                    }
                } header: {
                    HStack {
                        Text("Found (\(newIndices.count))")
                        Spacer()
                        if !newIndices.isEmpty {
                            Button(allNewSelected ? "Deselect all" : "Select all") {
                                for index in newIndices {
                                    rows[index].include = !allNewSelected
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                Section {
                    Button {
                        showingMerchants = true
                    } label: {
                        Label("Add a payment that's missing", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Choose any payment from your bank and add it as a fixed cost.")
                }

                if !existingIndices.isEmpty {
                    Section {
                        ForEach(existingIndices, id: \.self) { index in
                            FixedCostImportRowView(row: $rows[index], categories: categories, showsCategory: !isWizard)
                        }
                    } header: {
                        Text("Already in your fixed costs")
                    } footer: {
                        Text("These match fixed costs you already have, so they're not ticked. Tick one only if it's really a separate cost.")
                    }
                }

                if !isWizard {
                    Section {
                        Toggle("Also add them to the current period", isOn: $addToCurrentPeriod)
                    }
                }
            }
        }
        .navigationTitle("Import fixed costs")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !rows.isEmpty {
                Button {
                    addSelected()
                } label: {
                    Text(addButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCount == 0)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingMerchants) {
            NavigationStack {
                MerchantPickerView(merchants: merchants) { merchant in
                    addManual(merchant)
                }
            }
        }
        .task {
            await load()
        }
        .alert("Fixed costs added",
               isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") {
                resultMessage = nil
                dismiss()
            }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let from = Calendar.current.date(byAdding: .day, value: -185, to: .now) ?? .now
            let fetched = try await BankLink.fetchTransactions(context: context, from: from)
            let suggestions = RecurringDetector.detect(fetched.transactions, ownIBANs: fetched.ownIBANs)
            merchants = RecurringDetector.merchants(fetched.transactions, ownIBANs: fetched.ownIBANs)

            rows = suggestions.map { suggestion in
                let exists = alreadyExists(suggestion)
                var info = "\(suggestion.count)× in 6 months · last \(suggestion.lastDate.formatted(.dateTime.day().month(.abbreviated)))"
                if suggestion.amountVaries {
                    info += " · amount varies, typical amount shown"
                }
                // Irregular amounts with only a few payments are often shops, not fixed costs.
                let likelyFixed = !suggestion.amountVaries || suggestion.count >= 5
                return FixedCostImportRow(id: suggestion.id,
                                          include: !exists && likelyFixed,
                                          name: suggestion.name,
                                          amountText: suggestion.amount.editableAmount,
                                          frequency: suggestion.frequency,
                                          category: nil,
                                          isSavings: false,
                                          anchorDate: suggestion.lastDate,
                                          info: info,
                                          warning: suggestion.amountVaries,
                                          alreadyExists: exists)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Same merchant and a similar amount as a fixed cost you already have.
    private func alreadyExists(_ suggestion: RecurringSuggestion) -> Bool {
        if isWizard { return false }
        return templates.contains { template in
            if template.name.localizedCaseInsensitiveCompare(suggestion.name) == .orderedSame { return true }
            guard MerchantKey.make(template.name) == suggestion.merchantKey else { return false }
            return abs(template.amount - suggestion.amount) <= max(2, suggestion.amount * 0.25)
        }
    }

    private func addManual(_ merchant: MerchantSummary) {
        let id = "manual-" + merchant.id
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index].include = true
            return
        }
        rows.append(FixedCostImportRow(id: id,
                                       include: true,
                                       name: merchant.name,
                                       amountText: merchant.lastAmount.editableAmount,
                                       frequency: .monthly,
                                       category: nil,
                                       isSavings: false,
                                       anchorDate: merchant.lastDate,
                                       info: "Added by you · last paid \(merchant.lastDate.formatted(.dateTime.day().month(.abbreviated)))",
                                       warning: false,
                                       alreadyExists: false))
    }

    private func addSelected() {
        let chosen = rows.filter { $0.include && $0.isValid }

        if let onAddDrafts {
            let drafts = chosen.map { row in
                DraftFixedCost(name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                               amountText: row.amountText,
                               frequency: row.frequency,
                               mode: .whenDue,
                               anchorDate: row.anchorDate,
                               isSavings: row.isSavings)
            }
            onAddDrafts(drafts)
            dismiss()
            return
        }

        var order = (templates.map(\.sortOrder).max() ?? -1) + 1
        for row in chosen {
            let template = FixedCostTemplate(name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                             amount: row.amountText.parsedAmount ?? 0,
                                             frequency: row.frequency, mode: .whenDue,
                                             anchorDate: row.anchorDate, isSavings: row.isSavings,
                                             sortOrder: order)
            context.insert(template)
            template.category = row.category
            order += 1
        }
        try? context.save()

        var periodNote = ""
        if addToCurrentPeriod, let current = periods.last(where: { $0.isCurrent }) {
            let count = PeriodManager.addMissingDefaultFixedCosts(to: current, context: context)
            periodNote = " \(count) of them were added to the current period."
        }
        let added = chosen.count
        resultMessage = "Added \(added) fixed \(added == 1 ? "cost" : "costs") to your defaults." + periodNote
    }
}

struct FixedCostImportRowView: View {
    @Binding var row: FixedCostImportRow
    let categories: [BudgetCategory]
    let showsCategory: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                row.include.toggle()
            } label: {
                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(row.include ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $row.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    AmountField(placeholder: "0.00", text: $row.amountText)
                        .frame(width: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Menu {
                        Picker("How often", selection: $row.frequency) {
                            ForEach(CostFrequency.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(row.frequency.title)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.subheadline)
                    }
                }

                Text(row.info)
                    .font(.caption)
                    .foregroundStyle(row.warning ? Color.orange : Color.secondary)

                HStack {
                    if showsCategory {
                        CategoryMenu(categories: categories, selection: $row.category)
                    }
                    Spacer()
                    Toggle("Savings", isOn: $row.isSavings)
                        .toggleStyle(.button)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(row.include ? 1 : 0.7)
    }
}

/// Every payment you made, to add a missing fixed cost by hand.
struct MerchantPickerView: View {
    let merchants: [MerchantSummary]
    let onPick: (MerchantSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [MerchantSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return merchants }
        return merchants.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if merchants.isEmpty {
                Text("No payments found.").foregroundStyle(.secondary)
            }
            ForEach(filtered) { merchant in
                Button {
                    onPick(merchant)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(merchant.name)
                                .foregroundStyle(.primary)
                            Text("\(merchant.count)× · last \(merchant.lastDate.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(merchant.lastAmount.asCurrency)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search payments")
        .navigationTitle("Choose a payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// MARK: - Import: all transactions

struct TransactionImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]
    @Query private var expenses: [Expense]

    private struct Row: Identifiable {
        let transaction: FetchedTransaction
        var include: Bool
        var category: BudgetCategory?
        let note: String?
        var id: String { transaction.id }
    }

    @State private var fromDate: Date = .now
    @State private var didSetFromDate = false
    @State private var rows: [Row] = []
    @State private var skippedDuplicates = 0
    @State private var includeIncoming = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    private var visibleRows: [Row] {
        rows.filter { $0.transaction.isDebit || includeIncoming }
    }

    private var selectedCount: Int {
        visibleRows.filter(\.include).count
    }

    private var emptyText: String {
        skippedDuplicates > 0
            ? "No new transactions. \(skippedDuplicates) were already imported."
            : "No transactions in this period."
    }

    private var importButtonTitle: String {
        selectedCount == 1 ? "Import 1 transaction" : "Import \(selectedCount) transactions"
    }

    var body: some View {
        List {
            Section {
                DatePicker("From", selection: $fromDate, in: ...Date.now, displayedComponents: .date)
                Toggle("Include incoming money (as extra income)", isOn: $includeIncoming)
            } footer: {
                Text("Transfers between your own accounts and payments that look like fixed costs are unticked, so they aren't counted twice. Transactions you imported before are skipped.")
            }

            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading transactions…").foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if visibleRows.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach($rows) { $row in
                        if row.transaction.isDebit || includeIncoming {
                            transactionRow($row)
                        }
                    }
                } header: {
                    Text("\(visibleRows.count) transactions")
                } footer: {
                    if skippedDuplicates > 0 {
                        Text("\(skippedDuplicates) transactions were already imported and are hidden.")
                    }
                }
            }
        }
        .navigationTitle("Import transactions")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !visibleRows.isEmpty {
                Button {
                    importSelected()
                } label: {
                    Text(importButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCount == 0)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            if !didSetFromDate {
                fromDate = periods.last(where: { $0.isCurrent })?.startDate ?? .now
                didSetFromDate = true
            }
        }
        .task(id: fromDate) {
            guard didSetFromDate else { return }
            await load()
        }
        .alert("Import finished",
               isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") {
                resultMessage = nil
                dismiss()
            }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func transactionRow(_ row: Binding<Row>) -> some View {
        let transaction = row.wrappedValue.transaction
        return HStack(alignment: .top, spacing: 10) {
            Button {
                row.wrappedValue.include.toggle()
            } label: {
                Image(systemName: row.wrappedValue.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.wrappedValue.include ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.counterparty)
                    .lineLimit(1)
                Text("\(transaction.date.formatted(.dateTime.day().month(.abbreviated))) · \(transaction.accountName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = row.wrappedValue.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if transaction.isDebit {
                    CategoryMenu(categories: categories, selection: row.category)
                }
            }

            Spacer()

            Text((transaction.isDebit ? "− " : "+ ") + transaction.amount.asCurrency)
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundStyle(transaction.isDebit ? Color.primary : Color.green)
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await BankLink.fetchTransactions(context: context, from: fromDate)
            let alreadyImported = Set(expenses.map(\.externalID).filter { !$0.isEmpty })

            // Remember which category you used for a merchant before.
            var remembered: [String: BudgetCategory] = [:]
            for expense in expenses.sorted(by: { $0.date < $1.date }) where expense.source == "bank" {
                if let category = expense.category {
                    remembered[MerchantKey.make(expense.note)] = category
                }
            }

            let fixedKeys = Set(templates.map { MerchantKey.make($0.name) })
                .union(RecurringDetector.detect(fetched.transactions, ownIBANs: fetched.ownIBANs).map(\.merchantKey))

            var newRows: [Row] = []
            var duplicates = 0
            for transaction in fetched.transactions where transaction.date >= Calendar.current.startOfDay(for: fromDate) {
                if alreadyImported.contains(transaction.id) {
                    duplicates += 1
                    continue
                }
                let isOwnTransfer = fetched.ownIBANs.contains(transaction.counterpartyIBAN)
                let looksFixed = transaction.isDebit && fixedKeys.contains(transaction.merchantKey)
                var note: String?
                if isOwnTransfer {
                    note = "Transfer between your own accounts"
                } else if looksFixed {
                    note = "Looks like a fixed cost"
                }
                newRows.append(Row(transaction: transaction,
                                   include: !isOwnTransfer && !looksFixed,
                                   category: remembered[transaction.merchantKey],
                                   note: note))
            }
            rows = newRows
            skippedDuplicates = duplicates
        } catch {
            rows = []
            errorMessage = error.localizedDescription
        }
    }

    private func importSelected() {
        var expenseCount = 0
        var incomeCount = 0
        for row in visibleRows where row.include {
            let transaction = row.transaction
            if transaction.isDebit {
                let expense = Expense(amount: transaction.amount, date: transaction.date,
                                      note: transaction.counterparty, category: nil)
                expense.externalID = transaction.id
                expense.source = "bank"
                context.insert(expense)
                expense.category = row.category
                expenseCount += 1
            } else if let period = periods.first(where: { $0.contains(transaction.date) }) {
                let entry = IncomeEntry(name: transaction.counterparty, amount: transaction.amount, isExtra: true,
                                        date: transaction.date, sortOrder: 2000, sourceKey: "bank:" + transaction.id)
                context.insert(entry)
                entry.period = period
                incomeCount += 1
            }
        }
        try? context.save()

        var text = "Imported \(expenseCount) \(expenseCount == 1 ? "expense" : "expenses")"
        if incomeCount > 0 {
            text += " and \(incomeCount) extra income \(incomeCount == 1 ? "entry" : "entries")"
        }
        resultMessage = text + "."
    }
}
