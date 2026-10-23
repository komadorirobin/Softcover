import Foundation
import Security
import Darwin

struct HardcoverOAuthCredentials: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scope: String
    let sessionID: String

    var authorizationHeader: String { "Bearer \(accessToken)" }
    func needsRefresh(at date: Date = Date()) -> Bool { expiresAt <= date.addingTimeInterval(60) }
}

enum HardcoverOAuthConfiguration {
    static let authorizationEndpoint = URL(string: "https://hardcover.app/oauth2/authorize")!
    static let tokenEndpoint = URL(string: "https://api.hardcover.app/oauth2/token")!
    static let revocationEndpoint = URL(string: "https://api.hardcover.app/oauth2/revoke")!
    static let issuer = "https://api.hardcover.app"
    static let redirectURI = "softcover://oauth/callback"

    // These are the broadest scopes Softcover actually needs. Narrow variants
    // such as read:library:public would not permit a user to see their own
    // private library entries.
    static let scopes = [
        "read:me:content",
        "read:me:roles",
        "read:catalog",
        "read:goals",
        "read:journal",
        "read:library",
        "read:lists",
        "read:prompts",
        "read:social",
        "read:users",
        "write:catalog:edit",
        "write:library",
        "write:reviews",
        "write:social",
        "openid",
        "offline_access"
    ]

    static var clientID: String {
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "HardcoverOAuthClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundled.isEmpty, !bundled.contains("$(") { return bundled }
        return AppGroup.defaults.string(forKey: "HardcoverOAuthClientID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum HardcoverOAuthError: LocalizedError {
    case notConfigured
    case noCredentials
    case invalidResponse
    case server(String)
    case reauthorizationRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return NSLocalizedString("Hardcover sign-in is not configured in this build.", comment: "")
        case .noCredentials:
            return NSLocalizedString("Connect your Hardcover account to continue.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("Hardcover returned an unreadable sign-in response.", comment: "")
        case .server(let message):
            return message
        case .reauthorizationRequired:
            return NSLocalizedString("Your Hardcover session expired. Please connect your account again.", comment: "")
        }
    }
}

enum HardcoverOAuthCredentialsStore {
    private static let service = "komadori.softcover.oauth"
    private static let account = "hardcover"
    private static let accessGroup = "7G6FEZ22K2.komadori.Hardcover-Reading-Widget.shared"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    static func load() throws -> HardcoverOAuthCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw keychainError(status)
        }
        do { return try JSONDecoder().decode(HardcoverOAuthCredentials.self, from: data) }
        catch { throw HardcoverOAuthError.invalidResponse }
    }

    static func save(_ credentials: HardcoverOAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw keychainError(update) }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw keychainError(add) }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    private static func keychainError(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return HardcoverOAuthError.server(message)
    }
}

/// Keeps the legacy personal access-token fallback out of shared defaults.
/// Existing installs are migrated lazily by `HardcoverConfig` after the app and
/// widget have the shared Keychain entitlement.
enum HardcoverLegacyAPIKeyStore {
    private static let service = "komadori.softcover.oauth"
    private static let account = "hardcover-legacy-api-key"
    private static let accessGroup = "7G6FEZ22K2.komadori.Hardcover-Reading-Widget.shared"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    static func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { throw keychainError(status) }
        return value
    }

    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw keychainError(update) }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw keychainError(add) }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    private static func keychainError(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return HardcoverOAuthError.server(message)
    }
}

private struct HardcoverOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

private struct HardcoverOAuthServerError: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum HardcoverOAuthAPI {
    static func exchangeAuthorizationCode(_ code: String, verifier: String) async throws -> HardcoverOAuthCredentials {
        let clientID = HardcoverOAuthConfiguration.clientID
        guard !clientID.isEmpty else { throw HardcoverOAuthError.notConfigured }
        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": HardcoverOAuthConfiguration.redirectURI,
            "code_verifier": verifier,
            "client_id": clientID
        ])
        return credentials(from: response, sessionID: UUID().uuidString)
    }

    static func refresh(_ current: HardcoverOAuthCredentials) async throws -> HardcoverOAuthCredentials {
        let clientID = HardcoverOAuthConfiguration.clientID
        guard !clientID.isEmpty else { throw HardcoverOAuthError.notConfigured }
        let response = try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
            "client_id": clientID
        ])
        return credentials(from: response, sessionID: current.sessionID)
    }

    static func revoke(_ credentials: HardcoverOAuthCredentials) async throws {
        let clientID = HardcoverOAuthConfiguration.clientID
        guard !clientID.isEmpty else { throw HardcoverOAuthError.notConfigured }
        var request = URLRequest(url: HardcoverOAuthConfiguration.revocationEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Softcover/iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = formData([
            "token": credentials.refreshToken,
            "token_type_hint": "refresh_token",
            "client_id": clientID
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HardcoverOAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw HardcoverOAuthError.server(String(format: NSLocalizedString("Hardcover could not end the remote session (HTTP %d).", comment: ""), http.statusCode))
        }
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> HardcoverOAuthTokenResponse {
        var request = URLRequest(url: HardcoverOAuthConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Softcover/iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = formData(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HardcoverOAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let details = try? JSONDecoder().decode(HardcoverOAuthServerError.self, from: data)
            let message = details?.errorDescription ?? details?.error
                ?? String(format: NSLocalizedString("Hardcover sign-in failed (HTTP %d).", comment: ""), http.statusCode)
            throw HardcoverOAuthError.server(message)
        }
        do { return try JSONDecoder().decode(HardcoverOAuthTokenResponse.self, from: data) }
        catch { throw HardcoverOAuthError.invalidResponse }
    }

    private static func credentials(from response: HardcoverOAuthTokenResponse, sessionID: String) -> HardcoverOAuthCredentials {
        HardcoverOAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(max(60, response.expiresIn)),
            scope: response.scope ?? HardcoverOAuthConfiguration.scopes.joined(separator: " "),
            sessionID: sessionID)
    }

    private static func formData(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}

actor HardcoverOAuthSession {
    static let shared = HardcoverOAuthSession()

    func authorize(_ request: URLRequest) async throws -> URLRequest {
        guard request.url?.host?.lowercased() == "api.hardcover.app",
              let credentials = try HardcoverOAuthCredentialsStore.load() else { return request }
        let supplied = request.value(forHTTPHeaderField: "Authorization") ?? ""
        guard supplied.isEmpty || supplied == credentials.authorizationHeader else { return request }
        let current = try await validCredentials(credentials)
        var authorized = request
        authorized.setValue(current.authorizationHeader, forHTTPHeaderField: "Authorization")
        return authorized
    }

    func replacementAuthorization(afterUnauthorized authorization: String) async throws -> String? {
        guard let current = try HardcoverOAuthCredentialsStore.load() else { return nil }
        if current.authorizationHeader != authorization { return current.authorizationHeader }
        return try await refreshWithExclusiveLock(force: true, expectedAuthorization: authorization).authorizationHeader
    }

    private func validCredentials(_ credentials: HardcoverOAuthCredentials) async throws -> HardcoverOAuthCredentials {
        guard credentials.needsRefresh() else { return credentials }
        return try await refreshWithExclusiveLock(force: false)
    }

    private func refreshWithExclusiveLock(force: Bool, expectedAuthorization: String? = nil) async throws -> HardcoverOAuthCredentials {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) else {
            throw HardcoverOAuthError.reauthorizationRequired
        }
        let lockURL = container.appendingPathComponent("hardcover-oauth-refresh.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw HardcoverOAuthError.reauthorizationRequired
        }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        guard let latest = try HardcoverOAuthCredentialsStore.load() else { throw HardcoverOAuthError.noCredentials }
        if let expectedAuthorization, latest.authorizationHeader != expectedAuthorization { return latest }
        if !force, !latest.needsRefresh() { return latest }
        do {
            // Refresh tokens rotate. This call is deliberately never retried: an
            // ambiguous timeout could otherwise replay the old token and revoke
            // the entire token family.
            let refreshed = try await HardcoverOAuthAPI.refresh(latest)
            try HardcoverOAuthCredentialsStore.save(refreshed)
            return refreshed
        } catch {
            try? HardcoverOAuthCredentialsStore.delete()
            AppGroup.defaults.set(UUID().uuidString, forKey: "HardcoverAuthRevision")
            throw HardcoverOAuthError.reauthorizationRequired
        }
    }
}
