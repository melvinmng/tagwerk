import Foundation

/// Reads the open issues assigned to the token owner in the Tagwerk repository.
/// The repository issues endpoint rejects `assignee=@me`, so the login is resolved via `/user` first.
struct GitHubProbe: Probe {
    let name = "GitHub"

    static func makeUserRequest(token: String) -> URLRequest {
        authorized(URL(string: "https://api.github.com/user")!, token: token)
    }

    static func makeIssuesRequest(token: String, login: String) -> URLRequest {
        var components = URLComponents(string: "https://api.github.com/repos/melvinmng/tagwerk/issues")!
        components.queryItems = [
            URLQueryItem(name: "assignee", value: login),
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "1"),
        ]
        return authorized(components.url!, token: token)
    }

    static func parseLogin(_ body: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return json?["login"] as? String
    }

    static func interpret(status: Int, body: Data) -> ProbeResult {
        switch status {
        case 200:
            let issues = (try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]) ?? []
            return ProbeResult(name: "GitHub", ok: true, detail: "\(issues.count) Issue(s) gelesen")
        case 401:
            return ProbeResult(name: "GitHub", ok: false, detail: "HTTP 401: Token ungültig oder abgelaufen")
        case 403, 404:
            return ProbeResult(name: "GitHub", ok: false, detail: "HTTP \(status): Token hat keinen Zugriff auf das Repo")
        default:
            return ProbeResult(name: "GitHub", ok: false, detail: "HTTP \(status)")
        }
    }

    private static func authorized(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    func run() async -> ProbeResult {
        guard let token = Secrets.load(account: "github"), !token.isEmpty else {
            return ProbeResult(name: name, ok: false, detail: "Kein GitHub-Token gespeichert")
        }
        do {
            let (userData, userResponse) = try await URLSession.shared.data(for: Self.makeUserRequest(token: token))
            let userStatus = (userResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard userStatus == 200, let login = Self.parseLogin(userData) else {
                return Self.interpret(status: userStatus, body: userData)
            }
            let (data, response) = try await URLSession.shared.data(for: Self.makeIssuesRequest(token: token, login: login))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.interpret(status: status, body: data)
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Netzwerkfehler: \(error.localizedDescription)")
        }
    }
}
