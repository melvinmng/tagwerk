import SwiftUI
import TagwerkCore

/// Settings → Datensicherung → "Mit Passwort verschlüsseln" (DS6b). A forgotten password cannot be reset, so the warning stands
/// on top of the page and is repeated before the password is set. Tagwerk stores only the derived key in the Keychain of this
/// iPhone, never the password; the password fields never reach a log or an error message.
struct BackupEncryptionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var passwordSheet: PasswordPurpose?
    @State private var isConfirmingOff = false
    @State private var alertText: String?

    enum PasswordPurpose: Identifiable {
        case enable, change
        var id: Self { self }
    }

    var body: some View {
        let service = environment.backup
        let isOn = environment.settings.backupEncryptionEnabled
        let keyIsMissing = isOn && !service.hasKey
        Form {
            Section {
                warningBox
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Toggle("Mit Passwort verschlüsseln", isOn: Binding(
                    get: { isOn },
                    set: { wantsOn in
                        if wantsOn { passwordSheet = .enable } else { isConfirmingOff = true }
                    }))
                if isOn {
                    Button(keyIsMissing ? "Passwort erneut eingeben" : "Passwort ändern") { passwordSheet = .change }
                }
            } footer: {
                Text("Gilt für „Jetzt sichern“, die automatische Sicherung und Sicherheitskopien. Der Schlüssel liegt im Schlüsselbund dieses iPhones, damit automatisch gesichert werden kann. Auf einem neuen iPhone wirst du beim Wiederherstellen nach dem Passwort gefragt.")
            }

            if keyIsMissing {
                Section {
                    Label("Der Schlüssel fehlt auf diesem iPhone. Solange du das Passwort nicht erneut eingibst, sichert Tagwerk nichts.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orangeText)
                }
            }

            if isOn {
                Section {
                    EmptyView()
                } footer: {
                    Text("Ein neues Passwort gilt nur für neue Sicherungen. Ältere Dateien behalten das Passwort, mit dem sie geschrieben wurden.")
                }
            }
        }
        .navigationTitle("Verschlüsselung")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $passwordSheet) { purpose in
            PasswordSheet(purpose: purpose) { material in
                do {
                    try service.enableEncryption(with: material)
                    return true
                } catch {
                    alertText = String(localized: "Der Schlüssel ließ sich nicht im Schlüsselbund speichern. Die Verschlüsselung wurde nicht eingeschaltet.")
                    return false
                }
            }
        }
        .confirmationDialog("Verschlüsselung ausschalten?", isPresented: $isConfirmingOff, titleVisibility: .visible) {
            Button("Ausschalten", role: .destructive) {
                do { try service.disableEncryption() } catch {
                    alertText = String(localized: "Der Schlüssel ließ sich nicht aus dem Schlüsselbund entfernen.")
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Neue Sicherungen sind danach unverschlüsselt. Vorhandene verschlüsselte Dateien bleiben, wie sie sind, und brauchen weiter ihr Passwort.")
        }
        .alert(alertText ?? "", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    /// The warning that stands above everything else.
    private var warningBox: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text("Ohne Passwort lässt sich eine verschlüsselte Sicherung nicht öffnen. Tagwerk kann es nicht zurücksetzen. Vergisst du es, ist die Sicherung unbrauchbar.")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backup.encryptionWarning")
    }
}

/// Two password fields, then a confirmation that repeats the warning, then the key is derived (off the main thread; the
/// derivation is deliberately slow) and handed to `onDerived`, which stores it and returns whether that worked.
private struct PasswordSheet: View {
    let purpose: BackupEncryptionView.PasswordPurpose
    let onDerived: (BackupCrypto.KeyMaterial) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""
    @State private var isConfirming = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passwort", text: $password).textContentType(.newPassword)
                    SecureField("Passwort wiederholen", text: $repeated).textContentType(.newPassword)
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.redText)
                    } else {
                        Text("Mindestens \(BackupCrypto.minimumPasswordLength) Zeichen. Notiere das Passwort an einem sicheren Ort: Tagwerk kennt es nicht und kann es nicht zurücksetzen.")
                    }
                }
                Section {
                    Button {
                        isConfirming = true
                    } label: {
                        if isWorking { ProgressView() } else { Text(purpose == .enable ? "Verschlüsselung einschalten" : "Passwort festlegen") }
                    }
                    .disabled(!isValid || isWorking)
                }
            }
            .navigationTitle(purpose == .enable ? "Passwort festlegen" : "Neues Passwort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(isWorking) }
            }
            .alert("Ohne Passwort ist die Sicherung unbrauchbar", isPresented: $isConfirming) {
                Button("Verstanden, verschlüsseln") { derive() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Ohne Passwort lässt sich eine verschlüsselte Sicherung nicht öffnen. Tagwerk kann es nicht zurücksetzen. Vergisst du es, ist die Sicherung unbrauchbar.")
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var isValid: Bool {
        password.count >= BackupCrypto.minimumPasswordLength && password == repeated
    }

    /// Shown only when there is something to fix: too short, or the two entries differ.
    private var problem: String? {
        if !password.isEmpty, password.count < BackupCrypto.minimumPasswordLength {
            return String(localized: "Das Passwort ist zu kurz.")
        }
        if !repeated.isEmpty, password != repeated { return String(localized: "Die beiden Eingaben stimmen nicht überein.") }
        return nil
    }

    private func derive() {
        isWorking = true
        let typed = password
        Task {
            let material = try? await Task.detached(priority: .userInitiated) { try BackupCrypto.deriveKey(password: typed) }.value
            isWorking = false
            guard let material else { return }
            password = ""
            repeated = ""
            if onDerived(material) { dismiss() }
        }
    }
}
