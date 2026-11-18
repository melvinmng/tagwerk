import SwiftUI

/// First-launch setup (mockup 4): one step at a time, each can be skipped.
struct SetupView: View {
    @State private var model: SetupModel
    @State private var loginModel: GitHubLoginModel
    @State private var chatGPTSignIn: ChatGPTSignInModel
    let onFinish: () async -> Void

    init(model: SetupModel, loginModel: GitHubLoginModel, chatGPTSignIn: ChatGPTSignInModel,
         onFinish: @escaping () async -> Void) {
        _model = State(initialValue: model)
        _loginModel = State(initialValue: loginModel)
        _chatGPTSignIn = State(initialValue: chatGPTSignIn)
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(SetupStep.allCases.enumerated()), id: \.element) { index, step in
                        stepRow(step, number: index + 1)
                    }
                }

                if let step = model.current {
                    Section {
                        Text(step.explanation)
                        if step == .github {
                            GitHubLoginView(model: loginModel) { model.markSignedIn() }
                        } else if step == .chatGPT {
                            // Mockup T1: the privacy notice sits above the button, where the decision is made.
                            Text(AIStatusMessage.privacyNotice)
                            if let message = chatGPTSignIn.message { AIStatusRow(message: message) }
                            if chatGPTSignIn.isSigningIn {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Anmeldung läuft …").foregroundStyle(.secondary)
                                }
                            } else {
                                Button("Mit ChatGPT anmelden") {
                                    Task { if await chatGPTSignIn.signIn() { model.markSignedIn() } }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Button(step == .planCalendar ? "Kalender „Tagwerk“ anlegen" : "Erlauben") { Task { await model.grant() } }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Überspringen") {
                            if step == .github { loginModel.cancel() }
                            model.skip()
                        }
                    } header: {
                        Text(step.title)
                    } footer: {
                        Text("Du kannst das später in den Einstellungen ändern.")
                    }
                }

            }
            .navigationTitle("Willkommen")
        }
        .interactiveDismissDisabled()
        .task {
            // The keychain is read after the setup appeared; an existing sign-in marks step 5 as done.
            if await chatGPTSignIn.isSignedIn() { model.noteChatGPTSignedIn() }
        }
        .onChange(of: model.isFinished) { _, finished in
            if finished { Task { await onFinish() } }
        }
    }

    private func stepRow(_ step: SetupStep, number: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(isDone(step) ? Color.green : Color.secondary.opacity(0.2))
                if isDone(step) {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black)
                } else {
                    Text("\(number)").font(.caption)
                }
            }
            .frame(width: 24, height: 24)
            Text(step.title)
            Spacer()
            if let result = model.results[step], result != .fullAccess {
                Text(step.notDoneLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func isDone(_ step: SetupStep) -> Bool {
        model.results[step] == .fullAccess
    }
}
