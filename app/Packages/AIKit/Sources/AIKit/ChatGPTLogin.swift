import AuthenticationServices
import Foundation
import UIKit

/// Shows the sign-in page and returns once it redirects to the callback scheme.
/// Throws `ChatGPTAuthError.cancelled` when the user closes it.
@MainActor
public protocol WebAuthenticating: AnyObject {
    func authenticate(url: URL, callbackScheme: String) async throws
}

/// Runs "Sign in with ChatGPT": loopback server ready → sign-in sheet → callback → token exchange.
@MainActor
public final class ChatGPTLogin {
    static let callbackScheme = "tagwerk"
    /// After the sheet closed via the redirect, the callback has already been captured.
    static let callbackGrace: TimeInterval = 5

    private let session: ChatGPTSessionStore
    private let authenticator: WebAuthenticating
    private let port: UInt16

    public init(session: ChatGPTSessionStore, authenticator: WebAuthenticating, port: UInt16 = 1455) {
        self.session = session
        self.authenticator = authenticator
        self.port = port
    }

    public func signIn() async throws {
        let attempt = try await session.beginLogin()
        let server = LoopbackServer(port: port, expectedState: attempt.state)
        try await server.start()
        do {
            do {
                try await authenticator.authenticate(url: attempt.url, callbackScheme: Self.callbackScheme)
            } catch {
                // Only a sheet closed before the callback arrived is a real cancellation.
                guard server.capturedURL != nil else { throw error }
            }
            let callback = try await server.waitForCallback(timeout: Self.callbackGrace)
            await server.stop()
            try await session.completeLogin(callback: callback, attempt: attempt)
        } catch {
            await server.stop()
            throw error
        }
    }
}

/// Production sheet backed by `ASWebAuthenticationSession`. Keeps a strong reference to the
/// session while it is shown.
@MainActor
public final class SystemWebAuthenticator: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    override public init() {
        super.init()
    }

    public func authenticate(url: URL, callbackScheme: String) async throws {
        defer { activeSession = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { _, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: ChatGPTAuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: ChatGPTAuthError.serverFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                continuation.resume(throwing: ChatGPTAuthError.serverFailed("The sign-in sheet could not be shown."))
            }
        }
    }

    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            return UIWindow(windowScene: scenes.first!)
        }
    }
}
