import SwiftUI

/// First-launch setup (mockup 4): one step at a time, each can be skipped.
struct SetupView: View {
    @State private var model: SetupModel
    @State private var loginModel: GitHubLoginModel
    let onFinish: () async -> Void

    init(model: SetupModel, loginModel: GitHubLoginModel, onFinish: @escaping () async -> Void) {
        _model = State(initialValue: model)
        _loginModel = State(initialValue: loginModel)
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
                        } else {
                            Button("Erlauben") { Task { await model.grant() } }
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

                Section {
                    Text("Termine und Aufgabentitel gehen nur an OpenAI, wenn du „Tag planen“ tippst.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Willkommen")
        }
        .interactiveDismissDisabled()
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
                Text("nicht erlaubt").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func isDone(_ step: SetupStep) -> Bool {
        model.results[step] == .fullAccess
    }
}
