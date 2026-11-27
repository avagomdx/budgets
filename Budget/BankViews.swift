import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Settings → Bank connections

struct BankSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BankConnection.createdAt) private var connections: [BankConnection]

    @AppStorage(BankSettings.appIDKey) private var appID = ""
    @AppStorage(BankSettings.redirectURLKey) private var redirectURL = ""

    @State private var hasKey = BankSettings.hasPrivateKey
    @State private var importingKey = false
    @State private var message: String?

    private var hasValidConnection: Bool {
        connections.contains { $0.isValid }
    }

    var body: some View {
        List {
            Section {
                TextField("Application ID", text: $appID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Button {
                    importingKey = true
                } label: {
                    HStack {
                        Label(hasKey ? "Replace private key (.pem)" : "Import private key (.pem)",
                              systemImage: "key")
                        Spacer()
                        if hasKey {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                TextField(BankSettings.defaultRedirectURL, text: $redirectURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote)
            } header: {
                Text("Enable Banking app")
            } footer: {
                Text("Use the application ID and the .pem file from your Enable Banking control panel. The key is stored in this iPhone's keychain and never leaves it, except to sign requests to Enable Banking. Leave the redirect URL empty to use the default; it must match the one registered in Enable Banking.")
            }

            Section {
                if connections.isEmpty {
                    Text("No banks connected yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(connections) { connection in
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
                        if let synced = connection.lastSyncedAt {
                            Text("Last import: \(synced.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    Label("Connect a bank", systemImage: "plus")
                }
                .disabled(appID.trimmingCharacters(in: .whitespaces).isEmpty || !hasKey)
            } header: {
                Text("Banks")
            } footer: {
                Text("Banks only allow access for a limited time (usually 90 or 180 days). After that, connect the bank again.")
            }

            Section {
                NavigationLink {
                    FixedCostImportView()
                } label: {
                    Label("Import fixed costs", systemImage: "repeat")
                }
                NavigationLink {
                    TransactionImportView()
                } label: {
                    Label("Import all transactions", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Fixed costs: finds recurring payments in the last six months and adds them as default fixed costs. All transactions: adds your payments as expenses, after you've reviewed them.")
            }
            .disabled(!hasValidConnection)
        }
        .navigationTitle("Bank connections")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importingKey, allowedContentTypes: [.item]) { result in
            importKey(result)
        }
        .alert("Bank connections",
               isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func importKey(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                guard let pem = String(data: data, encoding: .utf8) else {
                    throw BankError.invalidKey("the file isn't text.")
                }
                _ = try PrivateKeyLoader.secKey(fromPEM: pem)  // check it's usable before saving
                try Keychain.save(Data(pem.utf8), account: BankSettings.keychainAccount)
                hasKey = true
                message = "Private key imported. You can delete the .pem file from Files now."
            } catch {
                message = error.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
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

// MARK: - Import: fixed costs only

struct FixedCostImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \FixedCostTemplate.sortOrder) private var templates: [FixedCostTemplate]
    @Query(sort: \BudgetPeriod.startDate) private var periods: [BudgetPeriod]

    private struct Row: Identifiable {
        var suggestion: RecurringSuggestion
        var include: Bool
        var category: BudgetCategory?
        var isSavings: Bool
        let alreadyExists: Bool
        var id: String { suggestion.id }
    }

    @State private var rows: [Row] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var addToCurrentPeriod = true
    @State private var resultMessage: String?

    private var selectedCount: Int { rows.filter(\.include).count }

    private var addButtonTitle: String {
        selectedCount == 1 ? "Add 1 fixed cost" : "Add \(selectedCount) fixed costs"
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Looking for recurring payments…").foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if rows.isEmpty {
                ContentUnavailableView("No recurring payments found", systemImage: "repeat",
                                       description: Text("Nothing in the last six months looks like a weekly, monthly or quarterly payment."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach($rows) { $row in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                row.include.toggle()
                            } label: {
                                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(row.include ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.borderless)

                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Name", text: $row.suggestion.name)
                                    .font(.body)
                                Text(details(for: row))
                                    .font(.caption)
                                    .foregroundStyle(row.alreadyExists || row.suggestion.amountVaries ? Color.orange : Color.secondary)
                                HStack {
                                    CategoryMenu(categories: categories, selection: $row.category)
                                    Spacer()
                                    Toggle("Savings", isOn: $row.isSavings)
                                        .toggleStyle(.button)
                                        .font(.caption)
                                }
                            }

                            Text(row.suggestion.amount.asCurrency)
                                .monospacedDigit()
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Recurring payments")
                } footer: {
                    Text("Ticked items are added to your default fixed costs. Amounts that vary are shown as a typical (median) amount.")
                }

                Section {
                    Toggle("Also add them to the current period", isOn: $addToCurrentPeriod)
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

    private func details(for row: Row) -> String {
        var parts = ["\(row.suggestion.frequency.title)", "\(row.suggestion.count)×",
                     "last \(row.suggestion.lastDate.formatted(.dateTime.day().month(.abbreviated)))"]
        if row.suggestion.amountVaries { parts.append("amount varies") }
        if row.alreadyExists { parts.append("already in your fixed costs") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let from = Calendar.current.date(byAdding: .day, value: -185, to: .now) ?? .now
            let fetched = try await BankLink.fetchTransactions(context: context, from: from)
            let suggestions = RecurringDetector.detect(fetched.transactions, ownIBANs: fetched.ownIBANs)
            let existingKeys = Set(templates.map { MerchantKey.make($0.name) })
            rows = suggestions.map { suggestion in
                let exists = existingKeys.contains(suggestion.id)
                    || templates.contains { $0.name.localizedCaseInsensitiveCompare(suggestion.name) == .orderedSame }
                return Row(suggestion: suggestion,
                           include: !exists && !suggestion.amountVaries,
                           category: nil,
                           isSavings: false,
                           alreadyExists: exists)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSelected() {
        var order = (templates.map(\.sortOrder).max() ?? -1) + 1
        var added = 0
        for row in rows where row.include {
            let name = row.suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let template = FixedCostTemplate(name: name, amount: row.suggestion.amount,
                                             frequency: row.suggestion.frequency, mode: .whenDue,
                                             anchorDate: row.suggestion.lastDate, isSavings: row.isSavings,
                                             sortOrder: order)
            context.insert(template)
            template.category = row.category
            order += 1
            added += 1
        }
        try? context.save()

        var periodNote = ""
        if addToCurrentPeriod, let current = periods.last(where: { $0.isCurrent }) {
            let count = PeriodManager.addMissingDefaultFixedCosts(to: current, context: context)
            periodNote = " \(count) of them were added to the current period."
        }
        resultMessage = "Added \(added) fixed \(added == 1 ? "cost" : "costs") to your defaults." + periodNote
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
                .union(RecurringDetector.detect(fetched.transactions, ownIBANs: fetched.ownIBANs).map(\.id))

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
