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
    /// Test hook: called with the port the loopback server actually listens on, before the sheet opens.
    /// It differs from `port` only when port 0 was requested.
    var onListening: ((UInt16) -> Void)?

    public init(session: ChatGPTSessionStore, authenticator: WebAuthenticating, port: UInt16 = 1455) {
        self.session = session
        self.authenticator = authenticator
        self.port = port
    }

    public func signIn() async throws {
        let attempt = try await session.beginLogin()
        let server = LoopbackServer(port: port, expectedState: attempt.state)
        try await server.start()
        onListening?(server.listeningPort ?? port)
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
        // Fail early instead of presenting a sheet without an anchor window.
        guard Self.presentationWindow() != nil else {
            throw ChatGPTAuthError.serverFailed("The sign-in sheet could not be shown.")
        }
        defer { activeSession = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // The completion handler and a failed `start()` can both fire; the continuation must resume exactly once.
            let resumeOnce = SingleShotResume(continuation)
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { _, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    resumeOnce.resume(throwing: ChatGPTAuthError.cancelled)
                } else if let error {
                    resumeOnce.resume(throwing: ChatGPTAuthError.serverFailed(error.localizedDescription))
                } else {
                    resumeOnce.resume()
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                resumeOnce.resume(throwing: ChatGPTAuthError.serverFailed("The sign-in sheet could not be shown."))
            }
        }
    }

    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            // `authenticate` checked for a window before starting; an empty window is the safe fallback
            // if the last scene disappeared in between.
            Self.presentationWindow() ?? ASPresentationAnchor()
        }
    }

    /// The key window of any connected scene, otherwise a fresh window in the first scene.
    private static func presentationWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        return scenes.first.map { UIWindow(windowScene: $0) }
    }
}

/// Resumes a continuation at most once, from any thread; later calls are ignored.
private final class SingleShotResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        take()?.resume()
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let taken = continuation
        continuation = nil
        return taken
    }
}
