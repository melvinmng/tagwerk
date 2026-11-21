import SwiftUI
import TagwerkCore

/// Texts of the language settings that tests can check without a view.
enum LanguageSettingsText {
    /// The value of the row "Sprachen": the name of the dictation language ("Wie die App" shows the app language).
    static func summary(_ languages: ContentLanguages, locale: Locale = .current) -> String {
        name(languages.dictationLanguage(at: nil, locale: locale))
    }

    static func name(_ language: VoiceLanguage) -> String {
        language == .german ? String(localized: "Deutsch") : String(localized: "English")
    }
}

/// Einstellungen › Sprachen (mockup SP1b): the app language, the four content languages and the way to the voice settings.
struct LanguageSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    HStack {
                        Text("App-Sprache")
                        Spacer()
                        Text(LanguageSettingsText.name(.from(locale: .current))).foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.forward").font(.footnote).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
            } footer: {
                Text("Die Sprache der Oberfläche stellst du in den iOS-Einstellungen ein.")
            }

            Section {
                Picker("Diktat", selection: $settings.voiceRecognitionLanguage) {
                    Text("Wie die App").tag(VoiceChatLanguage.automatic)
                    ForEach(VoiceChatLanguage.choices, id: \.self) { Text(LanguageSettingsText.name($0)).tag($0.rawValue) }
                }
                Picker("Rezepte", selection: $settings.recipeLanguage) {
                    Text("Wie die App").tag(RecipeLanguage.automatic)
                    ForEach(RecipeLanguage.choices, id: \.self) { Text(LanguageSettingsText.name($0)).tag($0.rawValue) }
                }
                Picker("Einkaufsliste", selection: $settings.shoppingLanguage) {
                    Text("Wie Rezepte").tag(ContentLanguages.likeRecipes)
                    Text("Wie die App").tag(RecipeLanguage.automatic)
                    ForEach(RecipeLanguage.choices, id: \.self) { Text(LanguageSettingsText.name($0)).tag($0.rawValue) }
                }
                Picker("Sprachchat-Antwort", selection: answerLanguage) {
                    Text("Wie gesprochen").tag(ContentLanguages.spoken)
                    ForEach(VoiceChatLanguage.choices, id: \.self) { Text(LanguageSettingsText.name($0)).tag($0.rawValue) }
                }
            } header: {
                Text("Inhalte")
            } footer: {
                Text("Beim Diktieren und in der Einkaufsliste wechselst du die Sprache auch direkt am Feld. Rezepte übersetzt ChatGPT in die gewählte Sprache; die Artikel der Einkaufsliste entstehen in der Sprache der Einkaufsliste.")
            }

            Section {
                NavigationLink("Spracheingabe und Vorlesen") { VoiceSettingsView() }
            } header: {
                Text("Stimme")
            } footer: {
                Text("Mikrofon, Sprachpakete, Stimmen, Tempo und Sprechmodus.")
            }
        }
        .navigationTitle("Sprachen")
    }

    /// The answer language is stored as `nil` until the takeover ran; the picker shows "Wie gesprochen" for it.
    private var answerLanguage: Binding<String> {
        Binding(get: { environment.settings.voiceAnswerLanguage ?? ContentLanguages.spoken },
                set: { environment.settings.voiceAnswerLanguage = $0 })
    }
}
