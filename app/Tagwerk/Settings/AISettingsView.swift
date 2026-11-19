import AIKit
import SwiftUI

/// "Einstellungen › KI" (mockups K3, O1, P1–P4): ChatGPT account, model choice and privacy notice.
/// The model list loads when this page opens, at most once a day, or with "Liste aktualisieren".
struct AISettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var signIn: ChatGPTSignInModel?
    @State private var isLoadingModels = false
    @State private var modelError: String?

    private var ai: AIEnvironment { environment.ai }

    var body: some View {
        Form {
            accountSection
            if ai.isSignedIn { modelSection }
            if ai.isSignedIn, let model = ai.currentModel, !model.reasoningLevels.isEmpty { reasoningSection(model) }
            if ai.isSignedIn { planningSection }
            if ai.isSignedIn { PlanningRulesSection() }
            Section {
                NavigationLink("Datenschutzhinweis") { AIPrivacyView() }
            }
            #if DEBUG
            if ai.isSignedIn { ChatGPTCaptureSection() }
            #endif
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("KI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if signIn == nil { signIn = ChatGPTSignInModel(ai: ai) }
            await ai.refreshAccount()
            // No call on opening (§8.4): the cached list shows, "Liste aktualisieren" loads a new one.
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatGPT")
                    if ai.isSignedIn, let email = ai.accountEmail {
                        Text(email).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(ai.isSignedIn ? "angemeldet" : "nicht angemeldet")
                    .foregroundStyle(ai.isSignedIn ? Color.green : Color.secondary)
            }
            if ai.isSignedIn {
                Button("Abmelden", role: .destructive) {
                    Task { await ai.signOut() }
                }
            } else {
                if let message = signIn?.message { AIStatusRow(message: message) }
                if signIn?.isSigningIn == true {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Anmeldung läuft …").foregroundStyle(.secondary)
                    }
                } else {
                    Button("Mit ChatGPT anmelden") {
                        Task {
                            if await signIn?.signIn() == true { await loadModels(force: false) }
                        }
                    }
                }
            }
        } header: {
            Text("Konto")
        } footer: {
            if !ai.isSignedIn {
                Text("\(AIStatusMessage.privacyNotice)\n\nDie Anmeldung öffnet eine Seite von ChatGPT und kehrt danach von selbst zu Tagwerk zurück. Planen mit KI und der Assistent brauchen sie; alles andere läuft ohne.")
            }
        }
    }

    // MARK: Model

    private var modelSection: some View {
        @Bindable var ai = ai
        return Section {
            Picker("Modell", selection: $ai.selectedModelSlug) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatisch")
                    Text("Tagwerk nimmt das Standardmodell deines Abos").font(.footnote).foregroundStyle(.secondary)
                }
                .tag(String?.none)
                ForEach(ai.models) { model in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                        Text(model.slug).font(.footnote).foregroundStyle(.secondary)
                    }
                    .tag(String?.some(model.slug))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if isLoadingModels && ai.models.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Modelle werden geladen …").foregroundStyle(.secondary)
                }
            }
            if let modelError {
                AIStatusRow(message: AIStatusMessage(text: modelError, isWarning: true))
            }
            Button("Liste aktualisieren") { Task { await loadModels(force: true) } }
                .disabled(isLoadingModels)
        } header: {
            HStack {
                Text("Modell")
                Spacer()
                if let note = listNote { Text(note).textCase(nil) }
            }
        } footer: {
            Text("Gilt für Planen und Assistent. Ist das gewählte Modell nicht mehr verfügbar, wechselt Tagwerk auf „Automatisch“ und sagt es beim nächsten Aufruf.")
        }
    }

    // MARK: Planning (proposal 2026-11-18, §6)

    private var planningSection: some View {
        @Bindable var settings = environment.settings
        return Section {
            Toggle("Vorarbeiten, wenn Luft ist", isOn: $settings.aiWorkAhead)
            Picker("Längere Tage vorschlagen", selection: $settings.aiLongerDays) {
                Text("Nie").tag(AIPlanner.LongerDays.never.rawValue)
                Text("Bei Fristen und P1").tag(AIPlanner.LongerDays.forDeadlines.rawValue)
                Text("Nur im Notfall").tag(AIPlanner.LongerDays.emergencyOnly.rawValue)
            }
            NavigationLink { VoiceSettingsView() } label: {
                LabeledContent("Sprache", value: VoiceAvailability.summary(inputEnabled: environment.settings.voiceInputEnabled,
                                                                            readAloud: environment.settings.voiceReadAloud))
            }
            NavigationLink("Diagnose") { PlanningDiagnosticsView() }
            if ai.isSignedIn {
                NavigationLink("Sprachdienste prüfen") { VoiceDiagnosticsView(client: ai.client) }
            }
        } header: {
            Text("Planen mit KI")
        } footer: {
            Text("Längere Tage erscheinen immer nur als Vorschlag; erst dein ✓ ändert die Arbeitszeit des Tages.")
        }
    }

    // MARK: Reasoning

    /// "Denkaufwand": only the levels the chosen model offers; "Automatisch" leaves the model's default.
    private func reasoningSection(_ model: AIModel) -> some View {
        @Bindable var ai = ai
        let automatic = model.defaultReasoning.map { String(localized: "Standard: \(AIEnvironment.reasoningName($0).lowercased())") }
            ?? String(localized: "Standard des Modells")
        return Section {
            Picker("Denkaufwand", selection: $ai.selectedReasoning) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatisch")
                    Text(automatic).font(.footnote).foregroundStyle(.secondary)
                }
                .tag(String?.none)
                ForEach(model.reasoningLevels, id: \.self) { level in
                    Text(AIEnvironment.reasoningName(level)).tag(String?.some(level))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Denkaufwand")
        } footer: {
            Text("Gilt für Planen und Assistent. Höher denkt länger und gründlicher, braucht aber mehr Zeit und Kontingent.")
        }
    }

    private var listNote: String? {
        if isLoadingModels { return ai.models.isEmpty ? String(localized: "Liste wird geladen …") : String(localized: "wird aktualisiert …") }
        guard let fetchedAt = ai.modelsFetchedAt, !ai.models.isEmpty else { return nil }
        return String(localized: "Liste von ChatGPT · \(Self.relative(fetchedAt))")
    }

    private func loadModels(force: Bool) async {
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }
        do {
            try await ai.loadModels(force: force)
        } catch let error as ChatGPTError {
            if error == .notSignedIn {
                await ai.refreshAccount()
                signIn?.message = .expired
                return
            }
            modelError = ai.models.isEmpty
                ? String(localized: "Die Modellliste konnte nicht geladen werden. \(error.userMessage)")
                : String(localized: "Die Liste konnte nicht aktualisiert werden. \(error.userMessage)")
        } catch {
            modelError = String(localized: "Die Modellliste konnte nicht geladen werden.")
        }
    }

    /// "heute 09:12", "gestern 09:12" or "16.11. 09:12".
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "heute \(time)") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "gestern \(time)")
        }
        let day = date.formatted(.dateTime.day().month(.twoDigits))
        return "\(day) \(time)"
    }
}

/// "Datenschutzhinweis" (mockup Q1).
struct AIPrivacyView: View {
    var body: some View {
        Form {
            Section {
                Text(AIStatusMessage.privacyNotice)
                Text("Tagwerk ruft die KI nur auf, wenn du sie selbst startest, zum Beispiel mit „Tag planen“ oder einer Nachricht an den Assistenten. Im Hintergrund geschieht das nie, und Tagwerk fragt nicht bei jedem Aufruf erneut nach.")
                Text("Beim Planen geht je Aufgabe auch eine erwartete Dauer in Minuten mit, abgeleitet aus deinen bisherigen Messungen. Die Messungen selbst und die Labels bleiben auf dem iPhone. Abschalten kannst du das unter Einstellungen › Fokus-Timer.")
                Text("„Abmelden“ löscht die Anmeldung bei ChatGPT von diesem iPhone. Danach sind die KI-Funktionen aus, bis du dich wieder anmeldest.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Datenschutzhinweis")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Planungsvorgaben" (mockup VR1): at most five short sentences that go as text into every planning and
/// conversation. Tagwerk does not check whether the result keeps them.
struct PlanningRulesSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var draft: String?
    @State private var editingIndex: Int?

    var body: some View {
        let rules = environment.settings.aiPlanningRules
        Section {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                Button {
                    editingIndex = index
                    draft = rule
                } label: {
                    Text(rule)
                }
                .tint(.primary)
            }
            .onDelete { offsets in environment.settings.aiPlanningRules.remove(atOffsets: offsets) }
            if rules.count < AppSettings.maximumPlanningRules {
                Button {
                    editingIndex = nil
                    draft = ""
                } label: {
                    Label("Vorgabe hinzufügen", systemImage: "plus")
                }
            }
        } header: {
            Text("Planungsvorgaben · \(rules.count) von \(AppSettings.maximumPlanningRules)")
        } footer: {
            Text("Vorgaben gehen bei jeder Planung als Text an ChatGPT. Tagwerk prüft nicht, ob das Ergebnis sie einhält. Feste Zeiten für alles gehören in die Arbeitszeit.")
        }
        .alert(editingIndex == nil ? "Neue Vorgabe" : "Vorgabe", isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })) {
            TextField("z. B. Mails nicht nach 18 Uhr einplanen", text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
            Button("Sichern") { save() }
            Button("Abbrechen", role: .cancel) { draft = nil }
        } message: {
            Text("Nenne, woran die KI die Aufgaben erkennt, z. B. eine Liste oder ein Repo.")
        }
    }

    private func save() {
        let sentence = (draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draft = nil
        guard !sentence.isEmpty else { return }
        var rules = environment.settings.aiPlanningRules
        if let index = editingIndex, rules.indices.contains(index) {
            rules[index] = sentence
        } else {
            rules.append(sentence)
        }
        environment.settings.aiPlanningRules = rules
    }
}
