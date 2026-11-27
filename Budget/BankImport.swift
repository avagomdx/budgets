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
    var name: String
    let amount: Double
    let frequency: CostFrequency
    let count: Int
    let lastDate: Date
    let amountVaries: Bool
}

enum RecurringDetector {
    static func detect(_ transactions: [FetchedTransaction], ownIBANs: Set<String>,
                       now: Date = .now) -> [RecurringSuggestion] {
        let calendar = Calendar.current
        let debits = transactions.filter { $0.isDebit && !ownIBANs.contains($0.counterpartyIBAN) }
        let groups = Dictionary(grouping: debits) { $0.merchantKey }

        var suggestions: [RecurringSuggestion] = []
        for (key, items) in groups where !key.isEmpty && items.count >= 2 {
            let sorted = items.sorted { $0.date < $1.date }
            var intervals: [Int] = []
            for index in 1..<sorted.count {
                let days = calendar.dateComponents([.day], from: sorted[index - 1].date, to: sorted[index].date).day ?? 0
                if days > 0 { intervals.append(days) }
            }
            guard !intervals.isEmpty else { continue }
            let interval = median(intervals.map(Double.init))

            let frequency: CostFrequency
            if (6...8).contains(interval) && sorted.count >= 3 {
                frequency = .weekly
            } else if (25...35).contains(interval) && intervals.allSatisfy({ (20...40).contains($0) }) {
                frequency = .monthly
            } else if (85...95).contains(interval) {
                frequency = .quarterly
            } else {
                continue
            }

            // Still active: the last payment isn't much longer ago than the usual interval.
            guard let last = sorted.last else { continue }
            let daysSinceLast = calendar.dateComponents([.day], from: last.date, to: now).day ?? 0
            guard Double(daysSinceLast) <= interval * 1.5 + 10 else { continue }

            let amounts = sorted.map(\.amount)
            let typical = median(amounts)
            guard typical > 0 else { continue }
            let spread = ((amounts.max() ?? typical) - (amounts.min() ?? typical)) / typical

            suggestions.append(RecurringSuggestion(
                id: key,
                name: mostCommonName(in: sorted),
                amount: (typical * 100).rounded() / 100,
                frequency: frequency,
                count: sorted.count,
                lastDate: last.date,
                amountVaries: spread > 0.15
            ))
        }
        return suggestions.sorted { $0.amount > $1.amount }
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
