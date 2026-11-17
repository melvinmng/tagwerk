import GitHubKit
import SwiftUI

/// Device-flow login: shows the user code and opens github.com/login/device.
struct GitHubLoginView: View {
    @State private var model: GitHubLoginModel
    let onSignedIn: () -> Void
    @Environment(\.openURL) private var openURL

    init(model: GitHubLoginModel, onSignedIn: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                loginButton
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                loginButton
            case .requestingCode:
                ProgressView("Code wird angefordert …")
            case .showingCode(let code):
                codeView(code)
            case .signedIn(let name):
                Label("Angemeldet als \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .onChange(of: model.phase) { _, phase in
            if case .signedIn = phase { onSignedIn() }
        }
    }

    private var loginButton: some View {
        Button("Mit GitHub anmelden") { Task { await model.start() } }
    }

    @ViewBuilder
    private func codeView(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gib diesen Code auf GitHub ein:").font(.subheadline)
            Text(code.userCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
            Button("Code kopieren und GitHub öffnen") {
                UIPasteboard.general.string = code.userCode
                openURL(code.verificationURL)
            }
            .buttonStyle(.borderedProminent)  // explicit style: several buttons share this Form row
            HStack {
                ProgressView()
                Text("Warte auf Bestätigung …").foregroundStyle(.secondary)
            }
            Button("Abbrechen", role: .cancel) { model.cancel() }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
