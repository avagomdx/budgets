import Foundation
import Security

// MARK: - Settings

enum BankSettings {
    static let appIDKey = "enableBankingAppID"
    static let redirectURLKey = "enableBankingRedirectURL"
    static let defaultRedirectURL = "https://avagomdx.github.io/budgets/bank-callback.html"
    static let keychainAccount = "enable-banking-private-key"

    static var appID: String {
        UserDefaults.standard.string(forKey: appIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var redirectURL: String {
        let value = UserDefaults.standard.string(forKey: redirectURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultRedirectURL : value
    }

    static var hasPrivateKey: Bool {
        Keychain.load(account: keychainAccount) != nil
    }
}

// MARK: - Errors

enum BankError: LocalizedError {
    case missingAppID
    case missingKey
    case invalidKey(String)
    case signingFailed
    case http(Int, String)
    case badResponse
    case noCode(String)
    case stateMismatch
    case noConnections

    var errorDescription: String? {
        switch self {
        case .missingAppID:
            return "Enter your Enable Banking application ID first (Settings → Bank connections)."
        case .missingKey:
            return "Import your Enable Banking private key (.pem) first (Settings → Bank connections)."
        case .invalidKey(let reason):
            return "The private key couldn't be read: \(reason)"
        case .signingFailed:
            return "Signing the request with your private key failed."
        case .http(let status, let body):
            return "Enable Banking returned an error (\(status)): \(body)"
        case .badResponse:
            return "Enable Banking sent a response the app didn't understand."
        case .noCode(let reason):
            return "The bank didn't complete the connection: \(reason)"
        case .stateMismatch:
            return "This bank login doesn't match the one the app started. Please try connecting again."
        case .noConnections:
            return "There's no active bank connection. Connect a bank first, or reconnect one that expired."
        }
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.anthony.budget.enablebanking"

    static func save(_ data: Data, account: String) throws {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BankError.invalidKey("it couldn't be stored in the keychain (error \(status)).")
        }
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Private key and JWT

enum PrivateKeyLoader {
    /// Reads an RSA private key from PEM text ("BEGIN PRIVATE KEY" or "BEGIN RSA PRIVATE KEY").
    static func secKey(fromPEM pem: String) throws -> SecKey {
        let isPKCS8 = pem.contains("BEGIN PRIVATE KEY")
        let isPKCS1 = pem.contains("BEGIN RSA PRIVATE KEY")
        guard isPKCS8 || isPKCS1 else {
            throw BankError.invalidKey("this isn't a PEM private key file.")
        }
        let base64 = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let der = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            throw BankError.invalidKey("the file contents aren't valid base64.")
        }
        var keyData = der
        if isPKCS8 {
            keyData = try pkcs1(fromPKCS8: der)
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw BankError.invalidKey(message)
        }
        return key
    }

    /// PKCS#8 wraps the PKCS#1 key: SEQUENCE { INTEGER, SEQUENCE { OID, NULL }, OCTET STRING { PKCS#1 } }.
    static func pkcs1(fromPKCS8 der: Data) throws -> Data {
        let bytes = [UInt8](der)
        var index = 0

        func readHeader(expectedTag: UInt8) throws -> Int {
            guard index < bytes.count, bytes[index] == expectedTag else {
                throw BankError.invalidKey("unexpected key structure.")
            }
            index += 1
            guard index < bytes.count else { throw BankError.invalidKey("the key is truncated.") }
            var length = Int(bytes[index])
            index += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count > 0, count <= 4, index + count <= bytes.count else {
                    throw BankError.invalidKey("the key has an invalid length.")
                }
                length = 0
                for _ in 0..<count {
                    length = (length << 8) | Int(bytes[index])
                    index += 1
                }
            }
            return length
        }

        _ = try readHeader(expectedTag: 0x30)                 // outer SEQUENCE
        let versionLength = try readHeader(expectedTag: 0x02) // version INTEGER
        index += versionLength
        let algorithmLength = try readHeader(expectedTag: 0x30) // AlgorithmIdentifier SEQUENCE
        index += algorithmLength
        let keyLength = try readHeader(expectedTag: 0x04)     // OCTET STRING with the PKCS#1 key
        guard index + keyLength <= bytes.count else {
            throw BankError.invalidKey("the key is truncated.")
        }
        return Data(bytes[index..<(index + keyLength)])
    }

    static func loadStoredKey() throws -> SecKey {
        guard let data = Keychain.load(account: BankSettings.keychainAccount),
              let pem = String(data: data, encoding: .utf8) else {
            throw BankError.missingKey
        }
        return try secKey(fromPEM: pem)
    }
}

enum JWT {
    static func make(appID: String, key: SecKey, lifetime: TimeInterval = 3600) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = ["typ": "JWT", "alg": "RS256", "kid": appID]
        let payload: [String: Any] = [
            "iss": "enablebanking.com",
            "aud": "api.enablebanking.com",
            "iat": now,
            "exp": now + Int(lifetime),
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signingInput = base64URL(headerData) + "." + base64URL(payloadData)

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                                    Data(signingInput.utf8) as CFData, &error) as Data? else {
            throw BankError.signingFailed
        }
        return signingInput + "." + base64URL(signature)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - API types

struct ASPSP: Decodable, Identifiable, Hashable {
    let name: String
    let country: String
    let maximumConsentValidity: Int?
    let logo: String?

    var id: String { country + "/" + name }
}

private struct ASPSPList: Decodable {
    let aspsps: [ASPSP]
}

private struct AuthRequest: Encodable {
    struct Access: Encodable {
        let validUntil: String
        let balances: Bool
        let transactions: Bool
    }

    struct Bank: Encodable {
        let name: String
        let country: String
    }

    let access: Access
    let aspsp: Bank
    let state: String
    let redirectUrl: String
    let psuType: String
}

private struct AuthResponse: Decodable {
    let url: String
}

private struct SessionRequest: Encodable {
    let code: String
}

struct SessionResponse: Decodable {
    struct Account: Decodable {
        struct AccountID: Decodable {
            let iban: String?
        }

        let uid: String?
        let accountId: AccountID?
        let name: String?
        let currency: String?
    }

    struct Access: Decodable {
        let validUntil: String?
    }

    let sessionId: String
    let accounts: [Account]?
    let access: Access?
}

struct BankTransaction: Decodable {
    struct Money: Decodable {
        let amount: Double
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case amount, currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            if let text = try? container.decode(String.self, forKey: .amount) {
                amount = Double(text) ?? 0
            } else {
                amount = (try? container.decode(Double.self, forKey: .amount)) ?? 0
            }
        }
    }

    struct Party: Decodable {
        let name: String?
    }

    struct AccountRef: Decodable {
        let iban: String?
    }

    let entryReference: String?
    let transactionId: String?
    let transactionAmount: Money?
    let creditDebitIndicator: String?
    let status: String?
    let bookingDate: String?
    let valueDate: String?
    let transactionDate: String?
    let creditor: Party?
    let debtor: Party?
    let creditorAccount: AccountRef?
    let debtorAccount: AccountRef?
    let remittanceInformation: [String]?
}

private struct TransactionsResponse: Decodable {
    let transactions: [BankTransaction]?
    let continuationKey: String?
}

// MARK: - Client

struct EnableBankingClient {
    static let baseURL = URL(string: "https://api.enablebanking.com")!

    let appID: String
    let key: SecKey

    static func fromSettings() throws -> EnableBankingClient {
        let appID = BankSettings.appID
        guard !appID.isEmpty else { throw BankError.missingAppID }
        let key = try PrivateKeyLoader.loadStoredKey()
        return EnableBankingClient(appID: appID, key: key)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private func send<T: Decodable>(_ method: String, path: String, query: [URLQueryItem] = [],
                                    body: Data? = nil, as type: T.Type) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else { throw BankError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try JWT.make(appID: appID, key: key)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BankError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BankError.http(http.statusCode, String(text.prefix(300)))
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw BankError.badResponse
        }
    }

    func banks(country: String) async throws -> [ASPSP] {
        let list = try await send("GET", path: "aspsps", query: [URLQueryItem(name: "country", value: country)],
                                  as: ASPSPList.self)
        return list.aspsps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Starts the bank login and returns the URL to open in Safari.
    func startAuthorization(bank: ASPSP, state: String, redirectURL: String, validUntil: Date) async throws -> URL {
        let request = AuthRequest(
            access: AuthRequest.Access(validUntil: BankDates.isoString(validUntil), balances: true, transactions: true),
            aspsp: AuthRequest.Bank(name: bank.name, country: bank.country),
            state: state,
            redirectUrl: redirectURL,
            psuType: "personal"
        )
        let body = try Self.encoder.encode(request)
        let response = try await send("POST", path: "auth", body: body, as: AuthResponse.self)
        guard let url = URL(string: response.url) else { throw BankError.badResponse }
        return url
    }

    func createSession(code: String) async throws -> SessionResponse {
        let body = try Self.encoder.encode(SessionRequest(code: code))
        return try await send("POST", path: "sessions", body: body, as: SessionResponse.self)
    }

    /// All booked transactions since `from`, following pagination.
    func transactions(accountUID: String, from: Date) async throws -> [BankTransaction] {
        var all: [BankTransaction] = []
        var continuation: String?
        var pages = 0
        repeat {
            var query = [URLQueryItem(name: "date_from", value: BankDates.dayString(from))]
            if let continuation {
                query.append(URLQueryItem(name: "continuation_key", value: continuation))
            }
            let page = try await send("GET", path: "accounts/\(accountUID)/transactions", query: query,
                                      as: TransactionsResponse.self)
            all.append(contentsOf: page.transactions ?? [])
            continuation = page.continuationKey
            pages += 1
        } while continuation != nil && !(continuation ?? "").isEmpty && pages < 50
        return all
    }
}

// MARK: - Dates

enum BankDates {
    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parseISO(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func dayString(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 2000, components.month ?? 1, components.day ?? 1)
    }

    /// "2026-11-20" → noon on that day (local time), so it never shifts to another day.
    static func parseDay(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
