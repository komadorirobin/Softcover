import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
import UIKit

@MainActor
final class HardcoverOAuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isWorking = false
    private var webSession: ASWebAuthenticationSession?

    func signIn() async throws -> MeUser {
        guard !isWorking else { throw CancellationError() }
        guard !HardcoverOAuthConfiguration.clientID.isEmpty else { throw HardcoverOAuthError.notConfigured }
        isWorking = true
        defer { isWorking = false }

        let verifier = try randomURLSafeString(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = try randomURLSafeString(byteCount: 24)
        var components = URLComponents(url: HardcoverOAuthConfiguration.authorizationEndpoint,
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: HardcoverOAuthConfiguration.clientID),
            URLQueryItem(name: "redirect_uri", value: HardcoverOAuthConfiguration.redirectURI),
            URLQueryItem(name: "scope", value: HardcoverOAuthConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components.url else { throw HardcoverOAuthError.invalidResponse }

        let callback = try await openAuthorizationPage(authorizationURL)
        let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { values.first { $0.name == name }?.value }
        if let error = value("error") {
            throw HardcoverOAuthError.server(value("error_description") ?? error)
        }
        guard callback.scheme?.lowercased() == "softcover",
              callback.host?.lowercased() == "oauth",
              callback.path == "/callback",
              value("state") == state,
              value("iss") == HardcoverOAuthConfiguration.issuer,
              let code = value("code"), !code.isEmpty else {
            throw HardcoverOAuthError.invalidResponse
        }

        let candidate = try await HardcoverOAuthAPI.exchangeAuthorizationCode(code, verifier: verifier)
        let identity: MeUser
        do {
            identity = try await LibraryAPI.identity(authorization: candidate.authorizationHeader, fresh: true)
        } catch {
            try? await HardcoverOAuthAPI.revoke(candidate)
            throw error
        }

        let previous = try? HardcoverOAuthCredentialsStore.load()
        do { try HardcoverOAuthCredentialsStore.save(candidate) }
        catch {
            try? await HardcoverOAuthAPI.revoke(candidate)
            throw error
        }
        try? HardcoverLegacyAPIKeyStore.delete()
        AppGroup.defaults.removeObject(forKey: "HardcoverAPIKey")
        AppGroup.defaults.set(identity.username, forKey: "HardcoverUsername")
        markAccountChanged()
        if let previous, previous.refreshToken != candidate.refreshToken {
            try? await HardcoverOAuthAPI.revoke(previous)
        }
        return identity
    }

    /// Local credentials are always removed when the user disconnects. A
    /// revocation error is returned afterwards so the UI can explain that the
    /// remote session might still exist.
    func disconnect() async throws {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let credentials = try? HardcoverOAuthCredentialsStore.load()
        var revocationError: Error?
        if let credentials {
            do { try await HardcoverOAuthAPI.revoke(credentials) }
            catch { revocationError = error }
        }
        try? HardcoverOAuthCredentialsStore.delete()
        try? HardcoverLegacyAPIKeyStore.delete()
        AppGroup.defaults.removeObject(forKey: "HardcoverAPIKey")
        AppGroup.defaults.removeObject(forKey: "HardcoverUsername")
        markAccountChanged()
        if let revocationError { throw revocationError }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func openAuthorizationPage(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "softcover") { callback, error in
                Task { @MainActor in
                    guard !resumed else { return }
                    resumed = true
                    self.webSession = nil
                    if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: error ?? CancellationError()) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                resumed = true
                webSession = nil
                continuation.resume(throwing: HardcoverOAuthError.invalidResponse)
            }
        }
    }

    private func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else { throw HardcoverOAuthError.invalidResponse }
        return Data(bytes).base64URLEncodedString()
    }

    private func markAccountChanged() {
        AppGroup.defaults.set(UUID().uuidString, forKey: "HardcoverAuthRevision")
        Task { await HardcoverHTTP.shared.invalidate() }
        LibrarySnapshot.clear()
        WidgetSync.accountChanged()
        NotificationCenter.default.post(name: .hardcoverAccountDidChange, object: nil)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
