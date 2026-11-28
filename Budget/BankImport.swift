import Foundation
import SwiftData

// MARK: - Normalized transaction

struct FetchedTransaction: Identifiable, Hashable {
    /// Bank transaction ID (or a stable fallback), used to skip duplicates.
    let id: String
    let date: Date
    /// Always positive.
    let amount: Double
    let isDebit: Bool
    let counterparty: String
    let details: String
    let counterpartyIBAN: String
    let accountName: String
    let currency: String

    var merchantKey: String { MerchantKey.make(counterparty) }

    init?(_ transaction: BankTransaction, account: BankAccountLink) {
        if let status = transaction.status?.uppercased(), status == "PDNG" || status == "PEND" || status == "PENDING" {
            return nil
        }
        guard let money = transaction.transactionAmount else { return nil }
        let dateText = transaction.bookingDate ?? transaction.valueDate ?? transaction.transactionDate ?? ""
        guard let date = BankDates.parseDay(dateText) else { return nil }

        let indicator = transaction.creditDebitIndicator?.uppercased() ?? ""
        let isDebit = indicator.isEmpty ? money.amount < 0 : indicator == "DBIT"
        let remittance = (transaction.remittanceInformation ?? []).joined(separator: " ")
        let partyName = isDebit ? transaction.creditor?.name : transaction.debtor?.name
        let cleanedParty = (partyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        self.date = date
        self.amount = abs(money.amount)
        self.isDebit = isDebit
        self.counterparty = cleanedParty.isEmpty ? MerchantKey.displayName(fromDescription: remittance) : cleanedParty
        self.details = remittance
        self.counterpartyIBAN = ((isDebit ? transaction.creditorAccount?.iban : transaction.debtorAccount?.iban) ?? "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        self.accountName = account.displayName
        self.currency = money.currency ?? account.currency

        if let id = transaction.transactionId, !id.isEmpty {
            self.id = id
        } else if let reference = transaction.entryReference, !reference.isEmpty {
            self.id = reference
        } else {
            self.id = "\(account.uid)|\(dateText)|\(money.amount)|\(cleanedParty)|\(remittance.prefix(40))"
        }
    }
}

// MARK: - Recognizing the same merchant

enum MerchantKey {
    private static let phrases = ["apple pay", "google pay", "betaalpas", "contactless"]
    private static let stopWords: Set<String> = [
        "bea", "gea", "pas", "nr", "sepa", "incasso", "ideal", "overboeking", "periodieke", "doorlopende",
        "machtiging", "card", "payment", "to", "from", "naar", "van", "eur", "bv", "nv", "the", "de", "het",
        "transaction", "purchase", "ccv", "via", "kenmerk", "omschrijving", "iban", "bic", "naam", "id",
    ]

    /// Lowercase key of the first three meaningful words, e.g. "Vattenfall Klantenservice N.V." → "vattenfall klantenservice".
    static func make(_ text: String) -> String {
        tokens(text).prefix(3).joined(separator: " ")
    }

    static func tokens(_ text: String) -> [String] {
        var lower = text.lowercased()
        for phrase in phrases {
            lower = lower.replacingOccurrences(of: phrase, with: " ")
        }
        let letters = String(lower.map { $0.isLetter ? $0 : " " })
        return letters
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    /// A readable name from a payment description when there's no counterparty name.
    static func displayName(fromDescription text: String) -> String {
        let words = tokens(text).prefix(4).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let name = words.joined(separator: " ")
        return name.isEmpty ? "Bank transaction" : name
    }
}

// MARK: - Recurring payments → fixed cost suggestions

struct RecurringSuggestion: Identifiable {
    let id: String
    /// Merchant key (shared by payments with the same name).
    let merchantKey: String
    var name: String
    let amount: Double
    let frequency: CostFrequency
    let count: Int
    let lastDate: Date
    let amountVaries: Bool
}

/// One merchant you paid, for picking fixed costs by hand.
struct MerchantSummary: Identifiable {
    let id: String
    let name: String
    let lastAmount: Double
    let count: Int
    let lastDate: Date
}

enum RecurringDetector {
    /// Recurring payments (or, with `incoming: true`, recurring income such as salary and allowances).
    static func detect(_ transactions: [FetchedTransaction], ownIBANs: Set<String>,
                       now: Date = .now, incoming: Bool = false) -> [RecurringSuggestion] {
        let calendar = Calendar.current
        let relevant = transactions.filter { $0.isDebit != incoming && !ownIBANs.contains($0.counterpartyIBAN) }
        let groups = Dictionary(grouping: relevant) { $0.merchantKey }

        var suggestions: [RecurringSuggestion] = []
        for (merchant, merchantItems) in groups where !merchant.isEmpty && merchantItems.count >= 2 {
            // One payee can collect several different things (e.g. a bank: mortgage, account fee,
            // insurance). Treat each group of similar amounts separately.
            let clusters = amountClusters(merchantItems).filter { $0.count >= 2 }
            for (clusterIndex, items) in clusters.enumerated() {
            let key = clusters.count > 1 ? "\(merchant)~\(clusterIndex + 1)" : merchant
            let hint = clusters.count > 1 ? nameHint(for: items) : ""
            let sorted = items.sorted { $0.date < $1.date }

            // How many payments to this name are there in a typical month?
            let byMonth = Dictionary(grouping: sorted) { calendar.dateComponents([.year, .month], from: $0.date) }
            let perMonth = Int(median(byMonth.values.map { Double($0.count) }).rounded())

            if let whole = classify(sorted, now: now), whole.frequency == .weekly || perMonth < 2 {
                suggestions.append(suggestion(id: key, key: merchant, items: sorted, result: whole, suffix: hint))
                continue
            }

            // Several payments with the same name each month (e.g. a mortgage in two parts):
            // split them by size into separate series. Frequent shops (4+ a month) are skipped.
            guard (2...3).contains(perMonth) else { continue }
            var series: [[FetchedTransaction]] = Array(repeating: [], count: perMonth)
            for monthItems in byMonth.values {
                let bySize = monthItems.sorted { $0.amount > $1.amount }
                for (index, item) in bySize.enumerated() {
                    series[min(index, perMonth - 1)].append(item)
                }
            }
            for (index, part) in series.enumerated() where part.count >= 2 {
                let partSorted = part.sorted { $0.date < $1.date }
                guard let result = classify(partSorted, now: now), result.spread <= 0.25 else { continue }
                suggestions.append(suggestion(id: "\(key)#\(index + 1)", key: merchant, items: partSorted,
                                              result: result, suffix: hint + " (\(index + 1))"))
            }
            }
        }
        return suggestions.sorted { $0.amount > $1.amount }
    }

    /// Groups payments by similar amount (a new group starts at a jump of more than 25% or €5).
    static func amountClusters(_ items: [FetchedTransaction]) -> [[FetchedTransaction]] {
        var clusters: [[FetchedTransaction]] = []
        for item in items.sorted(by: { $0.amount < $1.amount }) {
            if let last = clusters.last, let previous = last.last {
                let mean = last.reduce(0) { $0 + $1.amount } / Double(last.count)
                if item.amount - previous.amount <= max(5, mean * 0.25) {
                    clusters[clusters.count - 1].append(item)
                    continue
                }
            }
            clusters.append([item])
        }
        return clusters
    }

    /// A few words from the payment description that aren't in the payee's name, e.g. " – Hypotheek Leningdeel".
    static func nameHint(for items: [FetchedTransaction]) -> String {
        guard let first = items.first else { return "" }
        let nameWords = Set(MerchantKey.tokens(first.counterparty))
        let descriptions = Dictionary(grouping: items.map(\.details)) { $0 }.mapValues(\.count)
        let common = descriptions.max { $0.value < $1.value }?.key ?? ""
        let words = MerchantKey.tokens(common)
            .filter { !nameWords.contains($0) && $0.count > 2 }
            .prefix(3)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? "" : " – " + words.joined(separator: " ")
    }

    private struct Classification {
        let frequency: CostFrequency
        let amount: Double
        let spread: Double
    }

    private static func classify(_ sorted: [FetchedTransaction], now: Date) -> Classification? {
        let calendar = Calendar.current
        var intervals: [Double] = []
        for index in 1..<sorted.count {
            let days = calendar.dateComponents([.day], from: sorted[index - 1].date, to: sorted[index].date).day ?? 0
            if days > 0 { intervals.append(Double(days)) }
        }
        guard !intervals.isEmpty else { return nil }
        let interval = median(intervals)

        let amounts = sorted.map(\.amount)
        let typical = median(amounts)
        guard typical > 0 else { return nil }
        let spread = ((amounts.max() ?? typical) - (amounts.min() ?? typical)) / typical

        guard let last = sorted.last else { return nil }
        let daysSinceLast = calendar.dateComponents([.day], from: last.date, to: now).day ?? 0

        // Weekly payments charged in batches, e.g. 2 × €8,99 on the same day every two weeks
        // (or 3 × after three weeks): the number of payments matches the number of weeks.
        let byDay = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.date) }
        if byDay.count >= 2, byDay.values.contains(where: { $0.count >= 2 }), spread <= 0.05,
           let firstDay = byDay.keys.min(), let lastDay = byDay.keys.max() {
            let span = calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0
            let paymentsBeforeLast = sorted.count - (byDay[lastDay]?.count ?? 0)
            let weeks = Double(span) / 7
            if span >= 14 && abs(Double(paymentsBeforeLast) - weeks) <= max(1, weeks * 0.2) && daysSinceLast <= 28 {
                return Classification(frequency: .weekly, amount: (typical * 100).rounded() / 100, spread: spread)
            }
        }

        let frequency: CostFrequency
        if (6...8).contains(interval) && sorted.count >= 3 {
            frequency = .weekly
        } else if (6...8).contains(interval) && sorted.count == 2 && spread <= 0.05 && daysSinceLast <= 14 {
            // A weekly payment that has only happened twice so far: same amount, one week apart, recent.
            frequency = .weekly
        } else if (25...35).contains(interval) {
            // Allow the odd skipped month (an interval of about two months).
            let regular = intervals.filter { (20...40).contains($0) || (50...70).contains($0) }.count
            guard Double(regular) >= 0.7 * Double(intervals.count) else { return nil }
            frequency = .monthly
        } else if (85...95).contains(interval) {
            frequency = .quarterly
        } else {
            return nil
        }

        // Still active: the last payment isn't much longer ago than the usual interval.
        guard Double(daysSinceLast) <= interval * 1.5 + 10 else { return nil }

        return Classification(frequency: frequency, amount: (typical * 100).rounded() / 100, spread: spread)
    }

    private static func suggestion(id: String, key: String, items: [FetchedTransaction],
                                   result: Classification, suffix: String) -> RecurringSuggestion {
        RecurringSuggestion(id: id,
                            merchantKey: key,
                            name: mostCommonName(in: items) + suffix,
                            amount: result.amount,
                            frequency: result.frequency,
                            count: items.count,
                            lastDate: items.last?.date ?? .now,
                            amountVaries: result.spread > 0.15)
    }

    /// Every merchant you paid, most recent first (for adding a fixed cost by hand).
    static func merchants(_ transactions: [FetchedTransaction], ownIBANs: Set<String>) -> [MerchantSummary] {
        let debits = transactions.filter { $0.isDebit && !ownIBANs.contains($0.counterpartyIBAN) }
        let groups = Dictionary(grouping: debits) { $0.merchantKey.isEmpty ? $0.counterparty : $0.merchantKey }

        var result: [MerchantSummary] = []
        for (key, items) in groups {
            // Amounts that come back (2× or more) get their own line, e.g. a mortgage and an account fee
            // from the same bank. The remaining one-off amounts stay together on one line.
            let clusters = amountClusters(items)
            let repeated = clusters.filter { $0.count >= 2 }
            let oneOffs = clusters.filter { $0.count < 2 }.flatMap { $0 }
            var parts: [[FetchedTransaction]] = repeated
            if !oneOffs.isEmpty { parts.append(oneOffs) }
            let splitNames = repeated.count > 1 || (repeated.count == 1 && !oneOffs.isEmpty)

            for (index, part) in parts.enumerated() {
                guard let last = part.max(by: { $0.date < $1.date }) else { continue }
                let isRepeated = index < repeated.count
                let name = mostCommonName(in: part) + (splitNames && isRepeated ? nameHint(for: part) : "")
                result.append(MerchantSummary(id: "\(key)~\(index)",
                                              name: name,
                                              lastAmount: isRepeated ? median(part.map(\.amount)) : last.amount,
                                              count: part.count,
                                              lastDate: last.date))
            }
        }
        return result.sorted { $0.lastDate > $1.lastDate }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func mostCommonName(in items: [FetchedTransaction]) -> String {
        let counts = Dictionary(grouping: items.map(\.counterparty)) { $0 }.mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? items.first?.counterparty ?? "Fixed cost"
    }
}

// MARK: - Connecting banks and fetching transactions

@MainActor
enum BankLink {
    private static let stateKey = "bankPendingState"
    private static let nameKey = "bankPendingName"
    private static let countryKey = "bankPendingCountry"
    private static let validUntilKey = "bankPendingValidUntil"

    /// Starts a bank login. Returns the URL to open in Safari.
    static func start(bank: ASPSP) async throws -> URL {
        let client = try EnableBankingClient.fromSettings()
        let state = UUID().uuidString
        let maxSeconds = Double(bank.maximumConsentValidity ?? 90 * 86_400)
        let seconds = max(min(maxSeconds, 180 * 86_400) - 3_600, 86_400)
        let validUntil = Date.now.addingTimeInterval(seconds)

        let defaults = UserDefaults.standard
        defaults.set(state, forKey: stateKey)
        defaults.set(bank.name, forKey: nameKey)
        defaults.set(bank.country, forKey: countryKey)
        defaults.set(validUntil.timeIntervalSince1970, forKey: validUntilKey)

        return try await client.startAuthorization(bank: bank, state: state,
                                                   redirectURL: BankSettings.redirectURL, validUntil: validUntil)
    }

    static func isCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "budgetapp" && url.host?.lowercased() == "bank-callback"
    }

    /// Finishes the bank login after the redirect back into the app. Returns a message for the user.
    static func handleCallback(_ url: URL, context: ModelContext) async throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw BankError.noCode(value("error_description") ?? error)
        }
        guard let code = value("code"), !code.isEmpty else {
            throw BankError.noCode("no authorization code was received.")
        }

        let defaults = UserDefaults.standard
        if let expected = defaults.string(forKey: stateKey), let received = value("state"), expected != received {
            throw BankError.stateMismatch
        }

        let client = try EnableBankingClient.fromSettings()
        let session = try await client.createSession(code: code)

        let pendingValidUntil = Date(timeIntervalSince1970: defaults.double(forKey: validUntilKey))
        let validUntil = session.access?.validUntil.flatMap(BankDates.parseISO) ?? pendingValidUntil
        let bankName = defaults.string(forKey: nameKey) ?? "Bank"
        let connection = BankConnection(sessionID: session.sessionId,
                                        bankName: bankName,
                                        bankCountry: defaults.string(forKey: countryKey) ?? "",
                                        validUntil: validUntil)
        context.insert(connection)

        var count = 0
        for account in session.accounts ?? [] {
            guard let uid = account.uid, !uid.isEmpty else { continue }
            let link = BankAccountLink(uid: uid,
                                       iban: account.accountId?.iban ?? "",
                                       name: account.name ?? "",
                                       currency: account.currency ?? "")
            context.insert(link)
            link.connection = connection
            count += 1
        }
        try? context.save()

        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: countryKey)
        defaults.removeObject(forKey: validUntilKey)

        return "\(bankName) is connected with \(count) \(count == 1 ? "account" : "accounts")."
    }

    /// Transactions from all active connections since `from`, plus the IBANs of your own accounts.
    static func fetchTransactions(context: ModelContext, from: Date) async throws
        -> (transactions: [FetchedTransaction], ownIBANs: Set<String>) {
        let connections = ((try? context.fetch(FetchDescriptor<BankConnection>())) ?? []).filter(\.isValid)
        guard !connections.isEmpty else { throw BankError.noConnections }

        let client = try EnableBankingClient.fromSettings()
        var result: [FetchedTransaction] = []
        var ownIBANs: Set<String> = []

        for connection in connections {
            for account in connection.accounts ?? [] {
                let iban = account.iban.replacingOccurrences(of: " ", with: "").uppercased()
                if !iban.isEmpty { ownIBANs.insert(iban) }
            }
        }

        for connection in connections {
            for account in (connection.accounts ?? []) where account.isEnabled {
                let raw = try await client.transactions(accountUID: account.uid, from: from)
                result.append(contentsOf: raw.compactMap { FetchedTransaction($0, account: account) })
            }
            connection.lastSyncedAt = .now
        }
        try? context.save()

        // The same transaction can show up twice (e.g. on both sides of an own transfer); keep one per ID.
        var seen: Set<String> = []
        let unique = result.filter { seen.insert($0.id).inserted }
        return (unique.sorted { $0.date > $1.date }, ownIBANs)
    }
}
